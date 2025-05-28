// Sources flattened with hardhat v2.23.0 https://hardhat.org

// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol@v5.2.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.20;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reininitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        assembly {
            $.slot := INITIALIZABLE_STORAGE
        }
    }
}


// File @openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol@v5.2.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)


/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}


// File @openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol@v5.2.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)



/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Ownable
    struct OwnableStorage {
        address _owner;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OwnableStorageLocation = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OwnableStorageLocation
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


// File contracts/adapters/interfaces/IProtocolAdapter.sol

// Original license: SPDX_License_Identifier: MIT

/**
 * @title IProtocolAdapter
 * @notice Enhanced interface for protocol adapters with consistent return values
 */
interface IProtocolAdapter {
    /**
     * @dev Supply assets to the underlying protocol
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of underlying tokens that were successfully supplied
     */
    function supply(address asset, uint256 amount) external returns (uint256);

    /**
     * @dev Withdraw assets from the underlying protocol
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @return The amount of underlying tokens successfully withdrawn
     */
    function withdraw(address asset, uint256 amount) external returns (uint256);

    /**
     * @dev Withdraw assets from the underlying protocol and send directly to a user
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @param user The address of the user to receive the withdrawn assets
     * @return The amount of underlying tokens successfully withdrawn and sent to user
     */
    function withdrawToUser(
        address asset,
        uint256 amount,
        address user
    ) external returns (uint256);

    /**
     * @dev Returns the calldata needed for the vault to approve the adapter to spend receipt tokens
     * @param asset The address of the underlying asset
     * @param amount The amount of receipt tokens to approve
     * @return target The target contract to call (the receipt token address)
     * @return data The calldata for the approval function
     */
    function getApprovalCalldata(
        address asset,
        uint256 amount
    ) external view returns (address target, bytes memory data);

    /**
     * @dev Harvest yield from the protocol by compounding interest
     * @param asset The address of the asset
     * @return harvestedAmount The total amount harvested in underlying asset terms
     */
    function harvest(address asset) external returns (uint256 harvestedAmount);

    /**
     * @dev Get the current APY for a specific asset
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view returns (uint256);

    /**
     * @dev Get the current balance in the protocol in underlying asset terms
     * @param asset The address of the asset
     * @return The current balance in underlying asset units
     */
    function getBalance(address asset) external view returns (uint256);

    /**
     * @dev Get the total principal amount deposited in this protocol
     * @param asset The address of the asset
     * @return The total principal amount in underlying asset units
     */
    function getTotalPrincipal(address asset) external view returns (uint256);

    /**
     * @dev Check if an asset is supported by this protocol adapter
     * @param asset The address of the asset to check
     * @return True if the asset is supported
     */
    function isAssetSupported(address asset) external view returns (bool);

    /**
     * @dev Get the name of the protocol
     * @return The name of the protocol
     */
    function getProtocolName() external view returns (string memory);

    /**
     * @dev Set the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @param amount The minimum reward amount
     */
    function setMinRewardAmount(address asset, uint256 amount) external;

    /**
     * @dev Get the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @return The minimum reward amount
     */
    function getEstimatedInterest(
        address asset
    ) external view returns (uint256);

    /**
     * @dev Get the receipt token for a specific asset
     * @param asset The address of the asset
     * @return The receipt token address
     */
    function getReceiptToken(address asset) external view returns (address);
}


// File contracts/core/interfaces/IRegistry.sol

// Original license: SPDX_License_Identifier: MIT
/**
 * @title IRegistry
 * @notice Interface for the protocol registry
 */
interface IRegistry {
    /**
     * @dev Register a protocol
     * @param protocolId The unique ID for the protocol
     * @param name The name of the protocol
     */
    function registerProtocol(uint256 protocolId, string memory name) external;

    /**
     * @dev Register an adapter for a specific protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @param adapter The address of the adapter
     */
    function registerAdapter(
        uint256 protocolId,
        address asset,
        address adapter
    ) external;

    /**
     * @dev Remove an adapter
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     */
    function removeAdapter(uint256 protocolId, address asset) external;

    /**
     * @dev Get the adapter for a specific protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @return The protocol adapter
     */
    function getAdapter(
        uint256 protocolId,
        address asset
    ) external view returns (IProtocolAdapter);

    /**
     * @dev Get all registered protocol IDs
     * @return Array of protocol IDs
     */
    function getAllProtocolIds() external view returns (uint256[] memory);

    /**
     * @dev Get the name of a protocol
     * @param protocolId The ID of the protocol
     * @return The name of the protocol
     */
    function getProtocolName(
        uint256 protocolId
    ) external view returns (string memory);

    /**
     * @dev Check if an adapter is registered for a protocol and asset
     * @param protocolId The ID of the protocol
     * @param asset The address of the asset
     * @return True if an adapter is registered
     */
    function hasAdapter(
        uint256 protocolId,
        address asset
    ) external view returns (bool);

    /**
     * @dev Transfer ownership of the registry
     * @param newOwner The address of the new owner
     */
    function transferOwnership(address newOwner) external;

    /**
     * @dev Set an authorized external caller (e.g., Yield Optimizer)
     * @param newCaller The address of the authorized caller
     */
    function setAuthorizedCaller(address newCaller) external;

    /**
     * @dev Add a protocol to active protocols (protocols with user funds)
     * @param protocolId The protocol ID to add to active protocols
     */
    function addActiveProtocol(uint256 protocolId) external;

    /**
     * @dev Remove a protocol from active protocols
     * @param protocolId The protocol ID to remove from active protocols
     */
    function removeActiveProtocol(uint256 protocolId) external;

    /**
     * @dev Replace an active protocol with another
     * @param oldProtocolId The protocol ID to remove from active protocols
     * @param newProtocolId The protocol ID to add to active protocols
     */
    function replaceActiveProtocol(uint256 oldProtocolId, uint256 newProtocolId) external;

    /**
     * @dev Get all active protocol IDs (protocols with user funds)
     * @return Array of active protocol IDs
     */
    function getActiveProtocolIds() external view returns (uint256[] memory);
}


// File contracts/core/ProtocolRegistry.sol

// Original license: SPDX_License_Identifier: MIT

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
