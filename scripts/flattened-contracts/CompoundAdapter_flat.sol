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


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v5.2.0

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)


/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
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


// File contracts/adapters/CompoundAdapter.sol

// Original license: SPDX_License_Identifier: MIT

/**
 * @title CompoundAdapter
 * @notice Adapter contract for interacting with Compound V3 (Comet) protocol
 * @dev This adapter handles deposits, withdrawals, and yield harvesting for Compound V3
 * 
 * Key Features:
 * - Direct interaction with Compound V3's Comet contracts
 * - Automatic interest accrual
 * - Principal tracking with interest compounding
 * - Safety checks and balance verifications
 */
/**
 * @title Simplified Compound V3 (Comet) Interface
 * @notice Contains only the methods used by CompoundAdapter
 */
interface CometMainInterface {
    // Supply and withdrawal methods
    function supplyTo(address dst, address asset, uint amount) external;
    function withdrawFrom(address src, address to, address asset, uint amount) external;
    
    // Interest rate calculation methods
    function getUtilization() external view returns (uint);
    function getSupplyRate(uint utilization) external view returns (uint64);
    
    // Account methods
    function accrueAccount(address account) external;
    function balanceOf(address owner) external view returns (uint256);
}

/**
 * @title ICometAllowance
 * @notice Interface for Compound V3's allowance management
 * @dev Handles manager permissions for account control
 */
interface ICometAllowance {
    /**
     * @notice Grants or revokes manager privileges
     * @param manager Address to grant/revoke privileges
     * @param isAllowed True to enable, false to disable
     */
    function allow(address manager, bool isAllowed) external;
    
    /**
     * @notice Checks manager permissions
     * @param owner Account owner address
     * @param manager Manager address to check
     * @return True if manager has permission
     */
    function isAllowed(address owner, address manager) external view returns (bool);
}

contract CompoundAdapter is
    IProtocolAdapter,
    Initializable,
    OwnableUpgradeable
{
    // Core Compound V3 contract for all operations
    CometMainInterface public comet;

    // Address that can call harvest and other management functions
    address public authorizedCaller;

    // Maps underlying assets to their Compound V3 representations
    mapping(address => address) public cTokens;

    // Tracks which assets are supported by this adapter
    mapping(address => bool) public supportedAssets;

    // Tracks total principal per asset including compounded interest
    mapping(address => uint256) public totalPrincipal;

    // Minimum reward threshold per asset for profitable harvesting
    mapping(address => uint256) public minRewardAmount;

    // Protocol identifier
    string private constant PROTOCOL_NAME = "Compound V3";

    // Events
    event Initialized(address indexed initializer);

    /**
     * @notice Ensures only owner or authorized caller can execute function
     * @dev Used for critical functions like harvest and supply
     */
    modifier onlyOwnerOrAuthorized() {
        require(
            msg.sender == owner() || msg.sender == authorizedCaller,
            "Not authorized"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the adapter with Compound V3 contract address
     * @dev Called during proxy deployment
     * @param _cometAddress Address of the Compound V3 Comet contract
     */
    function initialize(address _cometAddress) public initializer {
        require(_cometAddress != address(0), "Invalid Comet address");

        __Ownable_init(msg.sender);
        comet = CometMainInterface(_cometAddress);

        emit Initialized(msg.sender);
    }

    /**
     * @notice Adds a new asset to the adapter
     * @dev Maps underlying asset to its Compound V3 representation
     * @param asset The underlying asset address
     * @param cToken The Compound V3 token address
     */
    function addSupportedAsset(
        address asset,
        address cToken
    ) external onlyOwner {
        supportedAssets[asset] = true;
        cTokens[asset] = cToken;
    }

    /**
     * @notice Removes an asset from supported assets
     * @dev Prevents new deposits for the asset
     * @param asset The asset to remove
     */
    function removeSupportedAsset(address asset) external onlyOwner {
        supportedAssets[asset] = false;
    }

    /**
     * @notice Checks if an asset is supported by the adapter
     * @param asset The asset to check
     * @return True if the asset is supported
     */
    function isAssetSupported(
        address asset
    ) external view override(IProtocolAdapter) returns (bool) {
        return supportedAssets[asset];
    }

    /**
     * @notice Supplies assets to Compound V3
     * @dev Handles asset transfer, approval, and supply to Compound
     * @param asset The underlying asset address
     * @param amount Amount to supply
     * @return Amount successfully supplied
     */
    function supply(
        address asset,
        uint256 amount
    ) external override(IProtocolAdapter) onlyOwnerOrAuthorized returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        // Transfer and approve
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        IERC20(asset).approve(address(comet), amount);

        // Supply to Compound V3
        comet.supplyTo(msg.sender, asset, amount);
        totalPrincipal[asset] += amount;

        return amount;
    }

    /**
     * @notice Withdraws assets from Compound V3
     * @dev Handles balance checks and withdrawal from Compound
     * @param asset The underlying asset address
     * @param amount Amount to withdraw
     * @return Actual amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount
    ) external override(IProtocolAdapter) onlyOwnerOrAuthorized returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        // Calculate safe withdrawal amount
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal ? maxWithdrawal : amount;

        // Verify Compound balance
        uint256 cometBalanceBefore = comet.balanceOf(msg.sender);
        withdrawAmount = withdrawAmount > cometBalanceBefore ? cometBalanceBefore : withdrawAmount;

        if (withdrawAmount == 0) return 0;

        // Withdraw from Compound
        comet.withdrawFrom(msg.sender, msg.sender, asset, withdrawAmount);

        // Update principal
        if (withdrawAmount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= withdrawAmount;
        } else {
            totalPrincipal[asset] = 0;
        }

        return withdrawAmount;
    }

    /**
     * @notice Withdraws assets directly to user
     * @dev Similar to withdraw but sends assets directly to user
     * @param asset The underlying asset address
     * @param amount Amount to withdraw
     * @param user Address to receive withdrawn assets
     * @return Actual amount withdrawn
     */
    function withdrawToUser(
        address asset,
        uint256 amount,
        address user
    ) external override(IProtocolAdapter) onlyOwnerOrAuthorized returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(user != address(0), "Invalid user address");

        // Calculate safe withdrawal amount
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal ? maxWithdrawal : amount;

        // Verify Compound balance
        uint256 cometBalanceBefore = comet.balanceOf(msg.sender);
        withdrawAmount = withdrawAmount > cometBalanceBefore ? cometBalanceBefore : withdrawAmount;

        if (withdrawAmount == 0) return 0;

        // Withdraw directly to user
        comet.withdrawFrom(msg.sender, user, asset, withdrawAmount);

        // Update principal
        if (withdrawAmount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= withdrawAmount;
        } else {
            totalPrincipal[asset] = 0;
        }

        return withdrawAmount;
    }

    /**
     * @notice Gets calldata for Compound V3 allowance approval
     * @dev Returns data for the allow function call
     * @param asset The asset to approve (unused in Compound V3)
     * @param amount The amount to approve (unused in Compound V3)
     * @return target The Compound V3 contract address
     * @return data The allow function calldata
     */
    function getApprovalCalldata(
        address asset,
        uint256 amount
    ) external view override(IProtocolAdapter) returns (address target, bytes memory data) {
        require(supportedAssets[asset], "Asset not supported");

        return (
            address(comet),
            abi.encodeWithSelector(
                ICometAllowance.allow.selector,
                address(this),
                true
            ) 
        );
    }

    /**
     * @notice Gets total principal for an asset
     * @param asset The asset to check
     * @return Total principal amount
     */
    function getTotalPrincipal(
        address asset
    ) external view override(IProtocolAdapter) returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return totalPrincipal[asset];
    }

    /**
     * @notice Gets current APY for an asset
     * @dev Calculates APY from Compound V3's supply rate
     * @param asset The asset to check
     * @return APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override(IProtocolAdapter) returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        uint utilization = comet.getUtilization();
        uint64 supplyRatePerSecond = comet.getSupplyRate(utilization);
        
        // Convert per-second rate to annual rate in basis points
        uint256 SECONDS_PER_YEAR = 31536000;
        uint256 annualRateFraction = uint256(supplyRatePerSecond) * SECONDS_PER_YEAR;
        
        return (annualRateFraction * 10000) / 1e18;
    }

    /**
     * @notice Gets current balance in Compound V3
     * @param asset The asset to check
     * @return Current balance
     */
    function getBalance(
        address asset
    ) external view override(IProtocolAdapter) returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return totalPrincipal[asset];
    }

    /**
     * @notice Harvests accrued interest from Compound V3
     * @dev Updates total principal with current balance including interest
     * @param asset The asset to harvest
     * @return totalAssets Total assets including accrued interest
     */
    function harvest(
        address asset
    ) external override(IProtocolAdapter) onlyOwnerOrAuthorized returns (uint256 totalAssets) {
        require(supportedAssets[asset], "Asset not supported");

        if (totalPrincipal[asset] == 0) return 0;

        // Accrue interest
        comet.accrueAccount(msg.sender);

        // Get current balance including interest
        totalAssets = comet.balanceOf(msg.sender);
        
        // Update principal
        totalPrincipal[asset] = totalAssets;

        return totalAssets;
    }

    /**
     * @notice Sets minimum reward amount for profitable harvesting
     * @param asset The asset to configure
     * @param amount Minimum reward amount
     */
    function setMinRewardAmount(
        address asset,
        uint256 amount
    ) external override(IProtocolAdapter) {
        require(supportedAssets[asset], "Asset not supported");
        minRewardAmount[asset] = amount;
    }

    /**
     * @notice Gets estimated accrued interest
     * @dev Calculates interest based on current supply rate
     * @param asset The asset to check
     * @return Estimated interest amount
     */
    function getEstimatedInterest(
        address asset
    ) external view override(IProtocolAdapter) returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        uint utilization = comet.getUtilization();
        uint interestRate = comet.getSupplyRate(utilization);
        uint balance = comet.balanceOf(msg.sender);

        return (balance * interestRate) / 1e18;
    }

    /**
     * @notice Gets protocol name
     * @return Protocol name
     */
    function getProtocolName() external pure override(IProtocolAdapter) returns (string memory) {
        return PROTOCOL_NAME;
    }

    /**
     * @notice Gets receipt token for an asset
     * @dev In Compound V3, the Comet contract itself acts as receipt token
     * @param asset The asset to check
     * @return Comet contract address
     */
    function getReceiptToken(
        address asset
    ) external view override(IProtocolAdapter) returns (address) {
        require(supportedAssets[asset], "Asset not supported");
        return address(comet);
    }

    /**
     * @notice Sets authorized caller address
     * @param newCaller New authorized caller address
     */
    function setAuthorizedCaller(address newCaller) external onlyOwner {
        require(newCaller != address(0), "Invalid address");
        authorizedCaller = newCaller;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
