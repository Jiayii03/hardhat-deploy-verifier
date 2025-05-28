// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title CombinedVault
 * @notice A yield-generating vault that combines multiple DeFi protocols
 * @dev Implements ERC4626 with custom redemption rate mechanism
 * 
 * Key Features:
 * - Multi-protocol yield generation
 * - Dynamic asset distribution across protocols
 * - Redemption rate tracking for accurate share pricing
 * - Virtual vault integration for queued deposits
 * - Automatic yield harvesting and compounding
 * - Protocol management (add/remove/replace)
 * - Performance fee collection on yield
 * - Safety checks and balance verifications
 */

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IRegistry.sol";
import "../adapters/interfaces/IProtocolAdapter.sol";
import "./interfaces/IVault.sol";
import "./VirtualVault.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract CombinedVault is
    Initializable,
    ERC4626Upgradeable,
    IVault,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    // Protocol registry for managing adapters and active protocols
    IRegistry public registry;

    // Underlying asset (e.g., USDC)
    IERC20 private _asset;

    // Precision for calculations (12 decimals)
    uint256 public constant PRECISION = 1e12;

    // Redemption rate tracking (18 decimals precision)
    uint256 public redemptionRate; // Current rate for share/asset conversion
    uint256 public previousRedemptionRate; // Previous rate for change detection

    // Virtual vault for handling queued deposits
    VirtualVault public virtualVault;

    // Address that can call harvest and other management functions
    address public authorizedCaller;

    // Performance fee configuration
    address public treasury; // Address that receives performance fees
    uint256 public performanceFeeBps; // Fee in basis points (1% = 100, max 10% = 1000)
    uint256 public constant BASIS_POINTS = 10000; // 100%

    // Events
    event Deposited(
        address indexed user,
        uint256 assetAmount,
        uint256 shares,
        uint256 receiptTokenBalance,
        uint256 actualAssetValue,
        uint256 walletBalance,
        uint256 totalUserAssets,
        uint256 totalSupply,
        uint256 redemptionRate,
        uint256 depositTimestamp
    );
    event Withdrawn(
        address indexed user,
        uint256 assetAmount,
        uint256 shares,
        uint256 receiptTokenBalance,
        uint256 actualAssetValue,
        uint256 walletBalance,
        uint256 totalUserAssets,
        uint256 totalSupply,
        uint256 redemptionRate,
        uint256 withdrawTimestamp
    );
    event Harvested(
        uint256 timestamp,
        uint256 totalAssets,
        uint256 previousRedemptionRate,
        uint256 redemptionRate
    );
    event ProtocolAdded(uint256 indexed protocolId);
    event ProtocolRemoved(uint256 indexed protocolId);
    event AuthorizedCallerUpdated(
        address indexed previousCaller,
        address indexed newCaller
    );
    event Initialized(address indexed initializer);
    event VirtualVaultSet(address indexed virtualVault);
    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event PerformanceFeeCollected(uint256 amount, uint256 timestamp);
    event ReceivedAsset(address indexed sender, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Accepts any assets (ETH or ERC20) that are sent to the vault
     * @dev This function allows the vault to receive:
     *      - ETH via direct transfers or .call{value:...}("")
     *      - ERC20 tokens via transfer/transferFrom
     * All received assets can be swept to treasury using sweepAccidentalTokens:
     * - For ETH: sweepAccidentalTokens(address(0))
     * - For ERC20: sweepAccidentalTokens(tokenAddress)
     * - For USDC (vault's main asset): only excess above managed assets will be swept
     * This prevents assets from getting stuck in the vault
     */
    receive() external payable {
        emit ReceivedAsset(msg.sender, msg.value);
    }

    /**
     * @notice Fallback function to handle any calls to the contract
     * @dev This is required to properly handle payable conversions
     */
    fallback() external payable {
        emit ReceivedAsset(msg.sender, msg.value);
    }

    /**
     * @notice Ensures only owner or authorized caller can execute function
     * @dev Used for critical functions like harvest and protocol management
     */
    modifier onlyOwnerOrAuthorized() {
        require(
            msg.sender == owner() || msg.sender == authorizedCaller,
            "Not authorized"
        );
        _;
    }

    /**
     * @notice Ensures only virtual vault can deposit directly
     * @dev Used to restrict direct deposits to the vault
     */
    modifier onlyVirtualVault() {
        require(msg.sender == address(virtualVault), "Only virtual vault can deposit");
        _;
    }

    /**
     * @notice Initializes the vault with asset and registry
     * @dev Called during proxy deployment
     * @param assetAddress Address of the underlying asset
     * @param _registry Address of the protocol registry
     * @param _treasury Address that will receive performance fees
     * @param _performanceFeeBps Performance fee in basis points (1% = 100, max 10% = 1000)
     */
    function initialize(
        address assetAddress,
        address _registry,
        address _treasury,
        uint256 _performanceFeeBps
    ) public initializer {
        require(assetAddress != address(0), "Invalid asset");
        require(_registry != address(0), "Invalid registry");
        require(_treasury != address(0), "Invalid treasury");
        require(_performanceFeeBps <= 1000, "Fee too high"); // Max 10%

        __ERC4626_init(IERC20(assetAddress));
        __ERC20_init("Combined Vault Token", "cVT");
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);

        registry = IRegistry(_registry);
        _asset = IERC20(assetAddress);
        redemptionRate = 1e18; // Initial 1:1 rate
        treasury = _treasury;
        performanceFeeBps = _performanceFeeBps;

        emit Initialized(msg.sender);
    }

    /**
     * @notice Sets authorized caller address
     * @dev Used for automation contracts or yield optimizers
     * @param newCaller New authorized caller address
     */
    function setAuthorizedCaller(address newCaller) external onlyOwner {
        require(newCaller != address(0), "Invalid address");
        emit AuthorizedCallerUpdated(authorizedCaller, newCaller);
        authorizedCaller = newCaller;
    }

    /**
     * @notice Sets the virtual vault address
     * @dev Virtual vault handles queued deposits
     * @param _vault Address of the virtual vault
     */
    function setVirtualVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid address");
        virtualVault = VirtualVault(payable(_vault));
        emit VirtualVaultSet(_vault);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(
        address newOwner
    ) public override onlyOwner {
        require(
            newOwner != address(0),
            "CombinedVault: new owner is the zero address"
        );
        address oldOwner = owner();
        _transferOwnership(newOwner);
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @notice Adds a protocol to active protocols
     * @dev Verifies protocol registration and adapter availability
     * @param protocolId ID of the protocol to add
     */
    function addActiveProtocol(uint256 protocolId) external override(IVault) onlyOwnerOrAuthorized {
        require(
            bytes(registry.getProtocolName(protocolId)).length > 0,
            "Protocol not registered"
        );
        require(
            registry.hasAdapter(protocolId, address(_asset)),
            "No adapter for this asset"
        );

        registry.addActiveProtocol(protocolId);
        emit ProtocolAdded(protocolId);
    }

    /**
     * @notice Removes a protocol and redistributes assets
     * @dev Withdraws all funds before removal
     * @param protocolId ID of the protocol to remove
     */
    function removeActiveProtocol(uint256 protocolId) external override(IVault) onlyOwnerOrAuthorized {        
        uint256[] memory activeProtocols = registry.getActiveProtocolIds();
        require(activeProtocols.length > 1, "Cannot remove last protocol");

        _withdrawAllFromProtocol(protocolId);
        registry.removeActiveProtocol(protocolId);
        emit ProtocolRemoved(protocolId);

        uint256[] memory remainingProtocols = registry.getActiveProtocolIds();
        if (remainingProtocols.length > 0) {
            _distributeAssets();
        }
    }   

    /**
     * @notice Replaces one protocol with another
     * @dev Verifies new protocol registration and adapter
     * @param oldProtocolId ID of the protocol to replace
     * @param newProtocolId ID of the new protocol
     */
    function replaceActiveProtocol(
        uint256 oldProtocolId,
        uint256 newProtocolId
    ) external override(IVault) onlyOwner {
        require(
            bytes(registry.getProtocolName(newProtocolId)).length > 0,
            "New protocol not registered"
        );
        require(
            registry.hasAdapter(newProtocolId, address(_asset)),
            "No adapter for new protocol"
        );

        registry.replaceActiveProtocol(oldProtocolId, newProtocolId);
        emit ProtocolRemoved(oldProtocolId);
        emit ProtocolAdded(newProtocolId);
    }

    /**
     * @notice Calculates shares for a deposit amount
     * @dev Uses redemption rate for conversion
     * @param assets Amount of assets being deposited
     * @return shares Amount of shares to be minted
     */
    function previewDeposit(
        uint256 assets
    ) public view override(ERC4626Upgradeable, IVault) returns (uint256) {
        if (redemptionRate == 1e18) return assets; // 1:1 for first deposit
        return (assets * 1e18) / redemptionRate;
    }

    /**
     * @notice Calculates assets needed for desired shares
     * @dev Uses redemption rate with round-up for safety
     * @param shares Amount of shares desired
     * @return assets Amount of assets needed
     */
    function previewMint(
        uint256 shares
    ) public view override(ERC4626Upgradeable, IVault) returns (uint256) {
        if (redemptionRate == 1e18) return shares; // 1:1 for first deposit
        return Math.ceilDiv(shares * redemptionRate, 1e18);
    }

    /**
     * @notice Deposits assets into the vault
     * @dev Distributes assets across protocols and mints shares
     * @param assets Amount of assets to deposit
     * @param receiver Address receiving the shares
     * @return receiptTokens Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) public override(ERC4626Upgradeable, IVault) onlyVirtualVault nonReentrant returns (uint256) {
        require(receiver != address(0), "Invalid receiver");
        require(assets > 0, "Deposit must be > 0");

        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();
        require(activeProtocolIds.length > 0, "No active protocols");

        // Transfer and distribute
        SafeERC20.safeTransferFrom(_asset, msg.sender, address(this), assets);
        _distributeAssets();

        // Mint shares and emit event
        uint256 receiptTokens = convertToShares(assets);
        _mint(receiver, receiptTokens);

        uint256 walletBalance = _asset.balanceOf(receiver);
        uint256 vaultPosition = convertToAssets(balanceOf(receiver));
        uint256 totalUserAssets = walletBalance + vaultPosition;

        emit Deposited(
            receiver,
            assets,
            receiptTokens,
            balanceOf(receiver),
            vaultPosition,
            walletBalance,
            totalUserAssets,
            totalSupply(),
            redemptionRate,
            block.timestamp
        );

        return receiptTokens;
    }

    /**
     * @notice Converts assets to shares with round-up
     * @dev Internal helper for withdrawal calculations
     * @param assets Amount of assets to convert
     * @return shares Amount of shares
     */
    function convertAssetsToSharesRoundUp(uint256 assets) internal view returns (uint256) {
        if (redemptionRate == 1e18) return assets;
        return Math.ceilDiv(assets * 1e18, redemptionRate);
    }

    /**
     * @notice Withdraws assets from the vault
     * @dev Handles protocol withdrawals and share burning
     * @param assets Amount of assets to withdraw
     * @param receiver Address receiving the assets
     * @param owner Address that owns the shares
     * @return Amount of assets withdrawn
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override(ERC4626Upgradeable, IVault) returns (uint256) {
        require(assets > 0, "Withdraw amount must be > 0");
        require(receiver != address(0), "Invalid receiver");
        require(owner != address(0), "Invalid owner");

        // Check allowance for non-owner withdrawals
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                _approve(owner, msg.sender, allowed - assets);
            }
        }

        uint256 ownerBalanceBefore = balanceOf(owner);
        require(ownerBalanceBefore > 0, "No shares to withdraw");

        // Withdraw and burn
        uint256 actualWithdrawnAmount = _withdrawFromProtocols(assets, receiver);
        require(actualWithdrawnAmount > 0, "Withdrawal failed");

        uint256 sharesToBurn = Math.min(
            convertAssetsToSharesRoundUp(actualWithdrawnAmount),
            ownerBalanceBefore
        );

        _burn(owner, sharesToBurn);
        
        // Update redemption rate
        if (totalSupply() > 0) {
            redemptionRate = (totalAssets() * 1e18) / totalSupply();
        } else {
            redemptionRate = 1e18;
        }

        // Calculate and emit event
        uint256 walletBalance = _asset.balanceOf(owner);
        uint256 vaultPosition = convertToAssets(balanceOf(owner));
        uint256 totalUserAssets = walletBalance + vaultPosition;

        emit Withdrawn(
            owner,
            actualWithdrawnAmount,
            sharesToBurn,
            balanceOf(owner),
            vaultPosition,
            walletBalance,
            totalUserAssets,
            totalSupply(),
            redemptionRate,
            block.timestamp
        );

        return actualWithdrawnAmount;
    }

    /**
     * @notice Harvests yield and updates redemption rate
     * @dev Processes all protocols, collects performance fee, and flushes virtual vault if needed
     * Performance fee is calculated based on redemption rate increase and minted as shares to treasury
     * @return harvestedAmount Total assets after harvesting
     */
    function accrueAndFlush()
        external
        override(IVault)
        onlyOwnerOrAuthorized
        returns (uint256 harvestedAmount)
    {
        require(address(virtualVault) != address(0), "Virtual vault not set");

        // Harvest from all protocols
        uint256 totalAssets = _harvestAllProtocols();

        // Store previous rate before any updates
        previousRedemptionRate = redemptionRate;

        uint256 currentSupply = totalSupply();
        if (currentSupply == 0) {
            redemptionRate = 1e18;
        } else {
            // Calculate new redemption rate before fee
            uint256 newRedemptionRate = (totalAssets * 1e18) / currentSupply;
            
            // Only apply performance fee on positive gain
            if (newRedemptionRate > previousRedemptionRate) {
                uint256 gainPerShare = newRedemptionRate - previousRedemptionRate;
                uint256 performanceFeePerShare = (gainPerShare * performanceFeeBps) / BASIS_POINTS;
                
                // Calculate fee in assets
                uint256 feeAssets = (performanceFeePerShare * currentSupply) / 1e18;
                
                if (feeAssets > 0) {
                    // Calculate shares to mint to treasury based on fee assets
                    uint256 treasuryShares = (feeAssets * 1e18) / newRedemptionRate;

                    // Mint shares to treasury
                    _mint(treasury, treasuryShares);
                    emit PerformanceFeeCollected(feeAssets, block.timestamp);
                }
            }
            
            // Update redemption rate with new total supply
            redemptionRate = (totalAssets * 1e18) / totalSupply();
            if (redemptionRate == 0) {
                redemptionRate = 1e18;
            }
        }

        // Flush virtual vault if rate changed or empty
        if (previousRedemptionRate != redemptionRate || totalSupply() == 0) {
            virtualVault.flushToCombinedVault();
        }

        emit Harvested(
            block.timestamp,
            totalAssets,
            previousRedemptionRate,
            redemptionRate
        );
        return totalAssets;
    }

    /**
     * @notice Gets current redemption rate
     * @return Current redemption rate with 18 decimals
     */
    function getRedemptionRate() external view returns (uint256) {
        return redemptionRate;
    }

    /**
     * @notice Gets user's staked balance
     * @dev Excludes wallet balance
     * @param user Address of the user
     * @return stakedBalance Amount of assets staked
     */
    function getUserStakedBalance(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    /**
     * @notice Gets user's total balance including wallet
     * @dev Includes both staked and wallet balance
     * @param user Address of the user
     * @return totalBalance Total user balance
     */
    function getUserTotalBalance(address user) external view returns (uint256) {
        return _asset.balanceOf(user) + convertToAssets(balanceOf(user));
    }

    function balanceOf(
        address account
    ) public view override(ERC20Upgradeable, IERC20, IVault) returns (uint256) {
        return super.balanceOf(account);
    }

    /**
     * @dev Internal function to distribute assets to protocols
     */
    function _distributeAssets() internal {
        // Get active protocols from registry
        uint256 balance = _asset.balanceOf(address(this));

        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();
        require(activeProtocolIds.length > 0, "No active protocols");

        if (balance == 0) return;

        // Calculate amount per protocol (even distribution for now)
        uint256 amountPerProtocol = balance / activeProtocolIds.length;

        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            IProtocolAdapter adapter = registry.getAdapter(
                protocolId,
                address(_asset)
            );
            require(address(adapter) != address(0), "Invalid adapter");

            // Approve the protocol adapter to spend our funds using SafeERC20
            SafeERC20.forceApprove(_asset, address(adapter), amountPerProtocol);

            // Supply to the protocol
            uint256 supplied = adapter.supply(
                address(_asset),
                amountPerProtocol
            );
        }
    }

    /**
     * @dev Internal function to withdraw from protocols
     * @param amount Amount to withdraw
     * @param user User to receive the withdrawn assets (if null, send to this contract)
     * @return Amount withdrawn
     */
    function _withdrawFromProtocols(
        uint256 amount,
        address user
    ) internal returns (uint256) {
        // Get active protocols from registry
        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();
        if (activeProtocolIds.length == 0 || amount == 0) return 0;

        uint256 totalWithdrawn = 0;

        for (uint i = 0; i < activeProtocolIds.length; i++) {
            // Calculate remaining amount to withdraw
            uint256 remaining = amount - totalWithdrawn;
            if (remaining == 0) break;

            // Get protocol balance
            IProtocolAdapter adapter = registry.getAdapter(activeProtocolIds[i], address(_asset));
            uint256 protocolBalance = adapter.getBalance(address(_asset));
            
            // If protocol has no balance, skip to next protocol
            if (protocolBalance == 0) continue;

            // Try to withdraw remaining amount from this protocol
            uint256 withdrawn = _withdrawFromSingleProtocol(
                activeProtocolIds[i],
                remaining,
                user
            );

            totalWithdrawn += withdrawn;
        }

        return totalWithdrawn;
    }

    function _withdrawFromSingleProtocol(
        uint256 protocolId, 
        uint256 amountPerProtocol,
        address user
    ) internal returns (uint256) {
        IProtocolAdapter adapter = registry.getAdapter(protocolId, address(_asset));
        
        // Get protocol's receipt token
        address receiptToken = adapter.getReceiptToken(address(_asset));
        require(receiptToken != address(0), "Invalid receipt token");
        
        // Get current balance of receipt tokens
        uint256 receiptTokenBalance = IERC20(receiptToken).balanceOf(address(this));
        
        if (receiptTokenBalance == 0) {
            return 0;
        }
        
        // Calculate how much we can withdraw
        uint256 withdrawAmount = receiptTokenBalance < amountPerProtocol
            ? receiptTokenBalance
            : amountPerProtocol;
        
        // Get approval instructions
        (address target, bytes memory data) = adapter.getApprovalCalldata(
            address(_asset),
            withdrawAmount
        );
        
        // Execute the approval call
        (bool success, ) = target.call(data);
        require(success, "Approval failed");
        
        // Withdraw using appropriate method
        uint256 withdrawn;
        if (user != address(0)) {
            withdrawn = adapter.withdrawToUser(address(_asset), withdrawAmount, user);
        } else {
            withdrawn = adapter.withdraw(address(_asset), withdrawAmount);
        }
        
        return withdrawn;
    }

    /**
     * @dev Internal function to withdraw all funds from a specific protocol
     * @param protocolId ID of the protocol
     */
    function _withdrawAllFromProtocol(uint256 protocolId) public onlyOwnerOrAuthorized {
        IProtocolAdapter adapter = registry.getAdapter(protocolId, address(_asset));

        // Get protocol's receipt token
        address receiptToken = adapter.getReceiptToken(address(_asset));
        require(receiptToken != address(0), "Invalid receipt token");

        // Get current balance of receipt tokens
        uint256 balance = IERC20(receiptToken).balanceOf(address(this));

        if (balance > 0) {
            // Get approval instructions from adapter
            (address target, bytes memory data) = adapter.getApprovalCalldata(
                address(_asset),
                balance
            );

            // Execute the approval call
            (bool success, ) = target.call(data);
            require(success, "Approval failed");

            // Withdraw all funds
            uint256 withdrawn = adapter.withdraw(address(_asset), balance);
            require(withdrawn > 0, "Withdrawal failed");
        }
    }

    /**
     * @dev Internal function to harvest yield from all protocols
     * @return totalAssets The total amount harvested from all protocols
     */
    function _harvestAllProtocols() internal returns (uint256 totalAssets) {
        // Get active protocols from registry
        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();
        for (uint i = 0; i < activeProtocolIds.length; i++) {
            uint256 protocolId = activeProtocolIds[i];
            IProtocolAdapter adapter = registry.getAdapter(
                protocolId,
                address(_asset)
            );
            
            // Harvest and get total assets (including yield)
            uint256 protocolAssets = adapter.harvest(address(_asset));
            if (protocolAssets > 0) {
                totalAssets += protocolAssets;
            }
        }
        return totalAssets;
    }

    /**
     * @dev Returns the address of the underlying token used for the Vault
     * @return The address of the underlying asset token
     */
    function asset()
        public
        view
        override(ERC4626Upgradeable, IVault)
        returns (address)
    {
        return address(_asset);
    }

    /**
     * @dev Returns the total amount of the underlying asset that is "managed" by Vault
     * @return totalManagedAssets The total amount of assets managed by the vault (in adapters only)
     */
    function totalAssets() public view override returns (uint256) {
        uint256 total = 0;
        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();

        for (uint i = 0; i < activeProtocolIds.length; i++) {
            IProtocolAdapter adapter = registry.getAdapter(
                activeProtocolIds[i],
                address(_asset)
            );
            total += adapter.getBalance(address(_asset));
        }

        return total; 
    }

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided
     * @param assets Amount of assets to convert
     * @return shares Amount of shares
     */
    function convertToShares(
        uint256 assets
    ) public view override(ERC4626Upgradeable, IVault) returns (uint256) {
        if (redemptionRate == 1e18) return assets;
        // Round down to avoid giving too many shares
        return (assets * 1e18) / redemptionRate;
    }

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided
     * @param shares Amount of shares to convert
     * @return assets Amount of assets
     */
    function convertToAssets(
        uint256 shares
    ) public view override(ERC4626Upgradeable, IVault) returns (uint256) {
        if (redemptionRate == 1e18) return shares;
        return Math.ceilDiv(shares * redemptionRate, 1e18);
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their redemption
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets that would be received
     */
    function previewRedeem(
        uint256 shares
    ) public view override(ERC4626Upgradeable, IVault) returns (uint256) {
        // Round down to ensure safety (avoid reverts)
        return convertToAssets(shares);
    }

    /**
     * @dev Burns shares from owner and sends assets to receiver
     * @param shares Amount of shares to redeem
     * @param receiver Address of the receiver
     * @param owner Address of the owner
     * @return assets Amount of assets withdrawn
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override(ERC4626Upgradeable, IVault) returns (uint256) {
        uint256 assets = previewRedeem(shares);
        withdraw(assets, receiver, owner);
        return assets;
    }

    /**
     * @notice Sets the performance fee
     * @param _performanceFeeBps New fee in basis points (1% = 100, max 10% = 1000)
     */
    function setPerformanceFee(uint256 _performanceFeeBps) external onlyOwner {
        require(_performanceFeeBps <= 1000, "Fee too high"); // Max 10%
        emit PerformanceFeeUpdated(performanceFeeBps, _performanceFeeBps);
        performanceFeeBps = _performanceFeeBps;
    }

    /**
     * @notice Sweeps accidentally transferred assets to treasury
     * @dev Only sweeps assets that are not part of the protocol's managed assets
     * @param token Address of the token to sweep (address(0) for ETH)
     */
    function sweepAccidentalTokens(address token) external onlyOwner {
        if (token == address(0)) {
            // Handle ETH
            uint256 balance = address(this).balance;
            require(balance > 0, "No ETH to sweep");
            (bool success, ) = treasury.call{value: balance}("");
            require(success, "ETH transfer failed");
        } else {
            // Handle ERC20 tokens
            uint256 vaultBalance = IERC20(token).balanceOf(address(this));
            require(vaultBalance > 0, "No tokens to sweep");

            // Special handling for vault's main asset (USDC)
            if (token == address(_asset)) {
                // Get total managed assets (in adapters only)
                uint256 managedAssets = totalAssets();
                // Calculate total balance (managed + additional)
                uint256 totalBalance = managedAssets + vaultBalance;
                // Only allow sweeping if there's excess balance
                require(totalBalance > managedAssets, "No excess assets to sweep");
                // Calculate excess amount to sweep (total - managed)
                uint256 excessAmount = totalBalance - managedAssets;
                // Transfer excess to treasury
                SafeERC20.safeTransfer(IERC20(token), treasury, excessAmount);
            } else {
                // For other tokens, sweep entire balance
                SafeERC20.safeTransfer(IERC20(token), treasury, vaultBalance);
            }
        }
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
