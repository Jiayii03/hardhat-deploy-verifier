// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ProtocolRegistry
 * @notice Registry for managing protocol adapters with allocation support
 * @dev Central registry for managing protocol adapters and their allocations
 * 
 * Key Features:
 * - Protocol registration and management
 * - Asset-specific adapter registration
 * - Active protocol tracking
 * - Protocol replacement functionality
 * - Access control for authorized callers
 * - Upgradeable contract design
 */

import "./interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ProtocolRegistry is IRegistry, Initializable, OwnableUpgradeable {
    // Protocol ID => Asset => Adapter
    mapping(uint256 => mapping(address => address)) public adapters;
    
    // Protocol ID => name
    mapping(uint256 => string) public protocolNames;
    
    // Valid protocol IDs
    uint256[] public protocolIds;
    
    // Array of active protocol IDs (protocols that have user funds)
    uint256[] public activeProtocolIds;
    
    // Authorized external caller (e.g., YieldOptimizer)
    address public authorizedCaller;

    // Events
    event ProtocolRegistered(uint256 indexed protocolId, string name);
    event AdapterRegistered(uint256 indexed protocolId, address indexed asset, address adapter);
    event AdapterRemoved(uint256 indexed protocolId, address indexed asset);
    event ActiveProtocolAdded(uint256 indexed protocolId);
    event ActiveProtocolRemoved(uint256 indexed protocolId);
    event ActiveProtocolReplaced(uint256 indexed oldProtocolId, uint256 indexed newProtocolId);
    event AuthorizedCallerUpdated(address indexed oldCaller, address indexed newCaller);
    event Initialized(address indexed initializer);

    /**
     * @notice Ensures only owner or authorized caller can execute function
     * @dev Used for critical functions like protocol registration and adapter management
     */
    modifier onlyOwnerOrAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizedCaller, "Caller is not authorized");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the registry
     * @dev Called during proxy deployment
     */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        emit Initialized(msg.sender);
    }
    
    /**
     * @notice Register a new protocol
     * @dev Adds a protocol to the registry with a unique ID
     * @param protocolId The unique ID for the protocol
     * @param name The name of the protocol
     */
    function registerProtocol(uint256 protocolId, string memory name) external override(IRegistry) onlyOwnerOrAuthorized {
        require(bytes(protocolNames[protocolId]).length == 0, "Protocol ID already used");
        require(bytes(name).length > 0, "Empty name");
        require(protocolIds.length < 100, "Too many protocols"); // Add reasonable limit
        
        protocolNames[protocolId] = name;
        protocolIds.push(protocolId);
        
        emit ProtocolRegistered(protocolId, name);
    }
    
    /**
     * @notice Register an adapter for a specific protocol and asset
     * @dev Maps an adapter to a protocol-asset pair
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @param adapter The address of the adapter
     */
    function registerAdapter(uint256 protocolId, address asset, address adapter) external override(IRegistry) onlyOwnerOrAuthorized {
        require(bytes(protocolNames[protocolId]).length > 0, "Protocol not registered");
        require(IProtocolAdapter(adapter).isAssetSupported(asset), "Asset not supported by adapter");
        
        adapters[protocolId][asset] = adapter;
        
        emit AdapterRegistered(protocolId, asset, adapter);
    }
    
    /**
     * @notice Remove an adapter from the registry
     * @dev Removes the mapping for a protocol-asset pair
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     */
    function removeAdapter(uint256 protocolId, address asset) external override(IRegistry) onlyOwnerOrAuthorized {
        require(adapters[protocolId][asset] != address(0), "Adapter not registered");
        
        delete adapters[protocolId][asset];
        
        emit AdapterRemoved(protocolId, asset);
    }
    
    /**
     * @notice Add a protocol to the active protocols list
     * @dev Adds a protocol to the list of protocols with user funds
     * @param protocolId The protocol ID to add
     */
    function addActiveProtocol(uint256 protocolId) external override(IRegistry) onlyOwnerOrAuthorized {
        require(bytes(protocolNames[protocolId]).length > 0, "Protocol not registered");
        
        // Check if already in the list
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            if (activeProtocolIds[i] == protocolId) {
                revert("Protocol already active");
            }
        }
        
        activeProtocolIds.push(protocolId);
        emit ActiveProtocolAdded(protocolId);
    }
    
    /**
     * @notice Remove a protocol from the active protocols list
     * @dev Removes a protocol from the list of protocols with user funds
     * @param protocolId The protocol ID to remove
     */
    function removeActiveProtocol(uint256 protocolId) external override(IRegistry) onlyOwnerOrAuthorized {
        bool found = false;
        
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            if (activeProtocolIds[i] == protocolId) {
                found = true;
                
                // Replace with the last element and pop
                activeProtocolIds[i] = activeProtocolIds[activeProtocolIds.length - 1];
                activeProtocolIds.pop();
                
                emit ActiveProtocolRemoved(protocolId);
                break;
            }
        }
        
        require(found, "Protocol not active");
    }
    
    /**
     * @notice Replace an active protocol with another
     * @dev Swaps one active protocol for another while maintaining the list
     * @param oldProtocolId The protocol ID to remove
     * @param newProtocolId The protocol ID to add
     */
    function replaceActiveProtocol(uint256 oldProtocolId, uint256 newProtocolId) external override(IRegistry) onlyOwnerOrAuthorized {
        require(bytes(protocolNames[newProtocolId]).length > 0, "New protocol not registered");
        
        bool found = false;
        
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            if (activeProtocolIds[i] == oldProtocolId) {
                found = true;
                activeProtocolIds[i] = newProtocolId;
                
                emit ActiveProtocolReplaced(oldProtocolId, newProtocolId);
                break;
            }
        }
        
        require(found, "Old protocol not active");
    }
    
    /**
     * @notice Set an authorized external caller
     * @dev Allows another contract (e.g., YieldOptimizer) to call restricted functions
     * @param newCaller The address of the new authorized contract
     */
    function setAuthorizedCaller(address newCaller) external override(IRegistry) onlyOwner {
        require(newCaller != address(0), "Invalid address");
        emit AuthorizedCallerUpdated(authorizedCaller, newCaller);
        authorizedCaller = newCaller;
    }

    /**
     * @notice Get the adapter for a specific protocol and asset
     * @dev Returns the adapter contract for a protocol-asset pair
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @return The protocol adapter
     */
    function getAdapter(uint256 protocolId, address asset) external view override(IRegistry) returns (IProtocolAdapter) {
        address adapterAddress = adapters[protocolId][asset];
        require(adapterAddress != address(0), "Adapter not found");
        
        return IProtocolAdapter(adapterAddress);
    }
    
    /**
     * @notice Get all registered protocol IDs
     * @return Array of protocol IDs
     */
    function getAllProtocolIds() external view override(IRegistry) returns (uint256[] memory) {
        return protocolIds;
    }
    
    /**
     * @notice Get all active protocol IDs
     * @return Array of active protocol IDs
     */
    function getActiveProtocolIds() external view override(IRegistry) returns (uint256[] memory) {
        return activeProtocolIds;
    }

    /**
     * @notice Get active protocol ID by index
     * @dev Returns the protocol ID at a specific index in the active protocols list
     * @param index The index in the active protocols list
     * @return The protocol ID
     */
    function getActiveProtocolIdByIndex(uint256 index) external view returns (uint256) {
        require(index < activeProtocolIds.length, "Index out of bounds");
        require(activeProtocolIds.length > 0, "No active protocols");
        return activeProtocolIds[index];
    }
    
    /**
     * @notice Get the name of a protocol
     * @param protocolId The ID of the protocol
     * @return The name of the protocol
     */
    function getProtocolName(uint256 protocolId) external view override(IRegistry) returns (string memory) {
        string memory name = protocolNames[protocolId];
        require(bytes(name).length > 0, "Protocol not registered");
        
        return name;
    }
    
    /**
     * @notice Check if an adapter is registered for a protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @return True if an adapter is registered
     */
    function hasAdapter(uint256 protocolId, address asset) external view override(IRegistry) returns (bool) {
        return adapters[protocolId][asset] != address(0);
    }

    /**
     * @notice Transfer ownership of the registry
     * @dev Override to satisfy both IRegistry and OwnableUpgradeable
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) public override(IRegistry, OwnableUpgradeable) {
        super.transferOwnership(newOwner);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}