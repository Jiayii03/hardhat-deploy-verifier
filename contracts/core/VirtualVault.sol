// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title VirtualVault
 * @notice A temporary vault for queuing deposits before they enter the main vault
 * @dev Implements ERC4626 with 1:1 share ratio and batch processing
 * 
 * Key Features:
 * - Queues user deposits for batch processing
 * - 1:1 share to asset ratio for simplicity
 * - Batch processing with configurable size
 * - Failed deposit handling and retry mechanism
 * - Enhanced security checks
 * - Detailed event tracking
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface ICombinedVault {
    function deposit(uint256 assets, address receiver) external returns (uint256);
}

contract VirtualVault is 
    Initializable,
    ERC4626Upgradeable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable 
{
    using SafeERC20 for IERC20;

    // The combined vault to which funds will be transferred
    ICombinedVault public combinedVault;

    // Queued user deposits for the current epoch
    struct QueuedDeposit {
        uint256 amount;    // Amount of assets queued
        bool exists;       // Whether user has a queued deposit
    }
    mapping(address => QueuedDeposit) public queuedDeposits;
    address[] public queuedUsers;

    // Address that can call flush and other management functions
    address public authorizedCaller;

    // Batch processing configuration
    uint256 public constant BATCH_SIZE = 50; // Process 50 users per batch
    uint256 public lastProcessedIndex; // Track processing progress

    // Failed deposit tracking
    struct FailedDeposit {
        uint256 amount;      // Amount that failed to process
        uint256 retryCount;  // Number of retry attempts
        uint256 lastAttempt; // Timestamp of last attempt
    }
    mapping(address => FailedDeposit) public failedDeposits;
    address[] public failedUsers;

    // Events
    event Initialized(address indexed initializer);
    event DepositFailed(address indexed user, uint256 amount, string reason);
    event DepositProcessed(address indexed user, uint256 amount);
    event VirtualDeposit(
        address indexed user, 
        uint256 amount,
        uint256 virtualShares,
        uint256 virtualBalance,
        uint256 queuedAmount,
        uint256 walletBalance,
        uint256 totalUserAssets,
        uint256 timestamp
    );
    
    event VirtualWithdraw(
        address indexed user,
        uint256 amount,
        uint256 virtualShares,
        uint256 virtualBalance,
        uint256 queuedAmount,
        uint256 walletBalance,
        uint256 totalUserAssets,
        uint256 timestamp
    );

    /**
     * @notice Accepts any assets (ETH or ERC20) that are sent to the vault
     * @dev This function allows the vault to receive:
     *      - ETH via direct transfers or .call{value:...}("")
     *      - ERC20 tokens via transfer/transferFrom
     * All received assets can be swept to owner using sweepAccidentalTokens:
     * - For ETH: sweepAccidentalTokens(address(0))
     * - For ERC20: sweepAccidentalTokens(tokenAddress)
     * - For main asset: only excess above managed assets will be swept
     * This prevents assets from getting stuck in the vault
     */
    receive() external payable {
        // Optional: emit an event for received ETH
        emit ReceivedAsset(msg.sender, msg.value);
    }

    /**
     * @notice Fallback function to handle any calls to the contract
     * @dev This is required to properly handle payable conversions
     */
    fallback() external payable {
        // Optional: emit an event for received ETH
        emit ReceivedAsset(msg.sender, msg.value);
    }

    event ReceivedAsset(address indexed sender, uint256 amount);

    /**
     * @notice Ensures only owner or authorized caller can execute function
     * @dev Used for critical functions like flush and retry
     */
    modifier onlyOwnerOrAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizedCaller, "Not authorized");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the virtual vault
     * @dev Called during proxy deployment
     * @param _asset The underlying asset token
     * @param _combinedVault Address of the main vault
     */
    function initialize(
        IERC20 _asset,
        address _combinedVault
    ) public initializer {
        require(address(_asset) != address(0), "Invalid asset");
        require(_combinedVault != address(0), "Invalid vault");
        
        __ERC4626_init(_asset);
        __ERC20_init("Virtual Vault Token", "vVT");
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);
        
        combinedVault = ICombinedVault(_combinedVault); 
        emit Initialized(msg.sender);
    }

    /**
     * @notice Sets authorized caller address
     * @param _caller New authorized caller address
     */
    function setAuthorizedCaller(address _caller) external onlyOwner {
        authorizedCaller = _caller;
    }

    /**
     * @notice Sets the combined vault address
     * @param _vault New combined vault address
     */
    function setCombinedVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        combinedVault = ICombinedVault(_vault);
    }

    /**
     * @notice Deposits assets into the virtual vault
     * @dev Mints 1:1 shares and queues deposit for processing
     * @param assets Amount of assets to deposit
     * @param receiver Address to receive shares (must be msg.sender)
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) public override(ERC4626Upgradeable) returns (uint256 shares) {
        require(assets > 0, "Deposit must be > 0");
        require(receiver == msg.sender, "Receiver must be sender");
        
        // Transfer and mint
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        shares = assets;
        _mint(msg.sender, shares);

        // Queue deposit
        if (!queuedDeposits[msg.sender].exists) {
            queuedUsers.push(msg.sender);
            queuedDeposits[msg.sender].exists = true;
        }
        queuedDeposits[msg.sender].amount += assets;

        // Calculate and emit events
        uint256 walletBalance = IERC20(asset()).balanceOf(msg.sender);
        uint256 totalUserAssets = walletBalance + queuedDeposits[msg.sender].amount;

        emit Deposit(msg.sender, msg.sender, assets, shares);
        emit VirtualDeposit(
            msg.sender,
            assets,
            shares,
            balanceOf(msg.sender),
            queuedDeposits[msg.sender].amount,
            walletBalance,
            totalUserAssets,
            block.timestamp
        );
        return shares;
    }

    /**
     * @notice Withdraws assets from the virtual vault
     * @dev Burns shares and returns queued assets
     * @param assets Amount of assets to withdraw
     * @param receiver Address to receive assets (must be owner)
     * @param owner Address that owns the shares (must be msg.sender)
     * @return shares Amount of shares burned
     */
    function withdraw(uint256 assets, address receiver, address owner) public override(ERC4626Upgradeable) returns (uint256 shares) {
        require(queuedDeposits[owner].amount >= assets, "Not enough queued");
        require(owner == msg.sender, "Only owner can withdraw");
        require(receiver == owner, "Receiver must be owner");
        
        shares = assets;
        _burn(owner, shares);

        // Update queue
        queuedDeposits[owner].amount -= assets;
        if (queuedDeposits[owner].amount == 0) {
            queuedDeposits[owner].exists = false;
            _removeQueuedUser(owner);
        }

        IERC20(asset()).safeTransfer(receiver, assets);

        // Calculate and emit events
        uint256 walletBalance = IERC20(asset()).balanceOf(owner);
        uint256 totalUserAssets = walletBalance + queuedDeposits[owner].amount;
        
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        emit VirtualWithdraw(
            owner,
            assets,
            shares,
            balanceOf(owner),
            queuedDeposits[owner].amount,
            walletBalance,
            totalUserAssets,
            block.timestamp
        );
        return shares;
    }

    /**
     * @notice Processes queued deposits in batches
     * @dev Transfers funds to combined vault and handles failures
     */
    function flushToCombinedVault() external onlyOwnerOrAuthorized nonReentrant {
        uint256 startIndex = lastProcessedIndex;
        uint256 endIndex = Math.min(startIndex + BATCH_SIZE, queuedUsers.length);
        
        if (startIndex >= queuedUsers.length) {
            lastProcessedIndex = 0;
            delete queuedUsers;
            return;
        }

        for (uint i = startIndex; i < endIndex; i++) {
            address user = queuedUsers[i];
            uint256 amount = queuedDeposits[user].amount;
            if (amount > 0) {
                uint256 initialAssetBalance = IERC20(asset()).balanceOf(address(this));
                uint256 initialUserShares = balanceOf(user);

                try this.processUserDeposit(user, amount) {
                    // Verify balances after deposit
                    uint256 finalAssetBalance = IERC20(asset()).balanceOf(address(this));
                    uint256 finalUserShares = balanceOf(user);

                    if (finalAssetBalance != initialAssetBalance - amount || 
                        finalUserShares != initialUserShares - amount) {
                        _handleFailedDeposit(user, amount, "Balance verification failed");
                        continue;
                    }

                    queuedDeposits[user].amount = 0;
                    queuedDeposits[user].exists = false;
                    emit DepositProcessed(user, amount);
                } catch {
                    _handleFailedDeposit(user, amount, "Deposit processing failed");
                    continue;
                }
            }
        }

        lastProcessedIndex = endIndex;

        if (endIndex >= queuedUsers.length) {
            lastProcessedIndex = 0;
            delete queuedUsers;
        }
    }

    /**
     * @notice Handles failed deposit processing
     * @dev Updates failed deposit tracking and emits event
     * @param user Address of the user
     * @param amount Amount that failed
     * @param reason Failure reason
     */
    function _handleFailedDeposit(address user, uint256 amount, string memory reason) internal {
        if (failedDeposits[user].amount == 0) {
            failedUsers.push(user);
        }
        
        failedDeposits[user].amount = amount;
        failedDeposits[user].retryCount++;
        failedDeposits[user].lastAttempt = block.timestamp;
        
        emit DepositFailed(user, amount, reason);
    }

    /**
     * @notice Retries failed deposits
     * @dev Moves failed deposits back to queue for retry
     * @param maxRetries Maximum number of retry attempts
     */
    function retryFailedDeposits(uint256 maxRetries) external onlyOwnerOrAuthorized {
        for (uint i = 0; i < failedUsers.length; i++) {
            address user = failedUsers[i];
            FailedDeposit storage deposit = failedDeposits[user];
            
            if (deposit.amount == 0 || deposit.retryCount >= maxRetries) {
                continue;
            }

            if (!queuedDeposits[user].exists) {
                queuedUsers.push(user);
                queuedDeposits[user].exists = true;
            }
            queuedDeposits[user].amount = deposit.amount;
            
            delete failedDeposits[user];
            failedUsers[i] = failedUsers[failedUsers.length - 1];
            failedUsers.pop();
            i--;
        }
    }

    /**
     * @notice Gets failed deposit information
     * @param user Address of the user
     * @return amount Failed amount
     * @return retryCount Number of retry attempts
     * @return lastAttempt Timestamp of last attempt
     */
    function getFailedDepositInfo(address user) external view returns (
        uint256 amount,
        uint256 retryCount,
        uint256 lastAttempt
    ) {
        FailedDeposit storage deposit = failedDeposits[user];
        return (deposit.amount, deposit.retryCount, deposit.lastAttempt);
    }

    /**
     * @notice Processes a single user's deposit
     * @dev Internal function called by flushToCombinedVault
     * @param user Address of the user
     * @param amount Amount to process
     */
    function processUserDeposit(address user, uint256 amount) external {
        require(msg.sender == address(this), "Only self-call allowed");
        
        IERC20 assetToken = IERC20(asset());
        SafeERC20.safeIncreaseAllowance(assetToken, address(combinedVault), amount);
        
        combinedVault.deposit(amount, user);
        _burn(user, amount);
    }

    /**
     * @notice Removes a user from the queue
     * @param user Address of the user to remove
     */
    function _removeQueuedUser(address user) internal {
        uint256 len = queuedUsers.length;
        for (uint256 i = 0; i < len; i++) {
            if (queuedUsers[i] == user) {
                queuedUsers[i] = queuedUsers[len - 1];
                queuedUsers.pop();
                break;
            }
        }
    }

    // 1:1 conversion functions
    function previewDeposit(uint256 assets) public view override(ERC4626Upgradeable) returns (uint256) {
        return assets;
    }
    function previewMint(uint256 shares) public view override(ERC4626Upgradeable) returns (uint256) {
        return shares;
    }
    function convertToShares(uint256 assets) public view override(ERC4626Upgradeable) returns (uint256) {
        return assets;
    }
    function convertToAssets(uint256 shares) public view override(ERC4626Upgradeable) returns (uint256) {
        return shares;
    }

    /**
     * @notice Gets queue processing status
     * @return totalUsers Total users in queue
     * @return processedUsers Number of processed users
     * @return remainingUsers Number of remaining users
     */
    function getQueueStatus() external view returns (
        uint256 totalUsers,
        uint256 processedUsers,
        uint256 remainingUsers
    ) {
        totalUsers = queuedUsers.length;
        processedUsers = lastProcessedIndex;
        remainingUsers = totalUsers > processedUsers ? totalUsers - processedUsers : 0;
    }

    /**
     * @notice Gets all failed deposits
     * @return users Array of user addresses
     * @return amounts Array of failed amounts
     */
    function getFailedDeposits() external view returns (
        address[] memory users,
        uint256[] memory amounts
    ) {
        uint256 count = 0;
        for (uint i = 0; i < queuedUsers.length; i++) {
            if (queuedDeposits[queuedUsers[i]].amount > 0) {
                count++;
            }
        }

        users = new address[](count);
        amounts = new uint256[](count);
        
        uint256 index = 0;
        for (uint i = 0; i < queuedUsers.length; i++) {
            address user = queuedUsers[i];
            uint256 amount = queuedDeposits[user].amount;
            if (amount > 0) {
                users[index] = user;
                amounts[index] = amount;
                index++;
            }
        }
    }

    /**
     * @notice Gets user's virtual staked balance
     * @param user Address of the user
     * @return totalStaked Total staked balance
     */
    function getUserVirtualStakedBalance(address user) external view returns (uint256) {
        return queuedDeposits[user].amount;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;

    function sweepAccidentalTokens(address token) external onlyOwner {
        if (token == address(0)) {
            // Handle ETH
            uint256 balance = address(this).balance;
            require(balance > 0, "No ETH to sweep");
            (bool success, ) = owner().call{value: balance}("");
            require(success, "ETH transfer failed");
        } else {
            // Handle ERC20 tokens
            uint256 vaultBalance = IERC20(token).balanceOf(address(this));
            require(vaultBalance > 0, "No tokens to sweep");

            // Special handling for vault's main asset (USDC)
            if (token == address(asset())) {
                // Get total managed assets (in queued deposits)
                uint256 managedAssets = 0;
                for (uint i = 0; i < queuedUsers.length; i++) {
                    managedAssets += queuedDeposits[queuedUsers[i]].amount;
                }
                // Only allow sweeping if there's excess balance
                require(vaultBalance > managedAssets, "No excess assets to sweep");
                uint256 excessAmount = vaultBalance - managedAssets;
                SafeERC20.safeTransfer(IERC20(token), owner(), excessAmount);
            } else {
                // For other tokens, sweep entire balance
                SafeERC20.safeTransfer(IERC20(token), owner(), vaultBalance);
            }
        }
    }
}
