// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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

/**
 * @title CombinedVault
 * @notice A yield-generating vault with improved time-weighted balance tracking
 * @dev Implements simple accounting without ERC20 shares
 */
contract CombinedVault is
    Initializable,
    ERC4626Upgradeable,
    IVault,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20 for IERC20;

    // Protocol registry
    IRegistry public registry;

    // Underlying asset (e.g., USDC)
    IERC20 private _asset;

    // Precision for calculations
    uint256 public constant PRECISION = 1e12;

    // Add redemption rate tracking
    uint256 public redemptionRate; // Initial 1:1 rate with 18 decimals precision
    uint256 public previousRedemptionRate; // Track previous redemption rate

    // Virtual vault
    VirtualVault public virtualVault;

    address public authorizedCaller;

    // Events
    event Deposited(
        address indexed user,
        uint256 assetAmount,
        uint256 depositTimestamp
    );
    event Withdrawn(address indexed user, uint256 amount);
    event Harvested(
        uint256 timestamp,
        uint256 totalAssets,
        uint256 oldRate,
        uint256 newRate
    );
    event ProtocolAdded(uint256 indexed protocolId);
    event ProtocolRemoved(uint256 indexed protocolId);
    event AuthorizedCallerUpdated(
        address indexed previousCaller,
        address indexed newCaller
    );
    event Initialized(address indexed initializer);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyOwnerOrAuthorized() {
        require(
            msg.sender == owner() || msg.sender == authorizedCaller,
            "Not authorized"
        );
        _;
    }

    /**
     * @dev Initializer function
     * @param assetAddress Address of the underlying asset
     * @param _registry Address of the protocol registry
     */
    function initialize(
        address assetAddress,
        address _registry
    ) public initializer {
        require(assetAddress != address(0), "Invalid asset");
        require(_registry != address(0), "Invalid registry");

        __ERC4626_init(IERC20(assetAddress));
        __ERC20_init("Combined Vault Token", "cVT");
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);

        registry = IRegistry(_registry);
        _asset = IERC20(assetAddress);
        redemptionRate = 1e18; // Initial 1:1 rate

        emit Initialized(msg.sender);
    }

    /**
     * @dev Allows the owner to set an authorized caller (e.g., YieldOptimizer or Chainlink automation).
     * @param newCaller The new authorized caller address.
     */
    function setAuthorizedCaller(address newCaller) external onlyOwner {
        require(newCaller != address(0), "Invalid address");
        emit AuthorizedCallerUpdated(authorizedCaller, newCaller);
        authorizedCaller = newCaller;
    }

    function setVirtualVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid address");
        virtualVault = VirtualVault(_vault);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(
        address newOwner
    ) public override(OwnableUpgradeable) {
        require(
            newOwner != address(0),
            "CombinedVault: new owner is the zero address"
        );
        address oldOwner = owner();
        _transferOwnership(newOwner);
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev Add a protocol to active protocols
     * @param protocolId ID of the protocol to add
     */
    function addActiveProtocol(uint256 protocolId) external override onlyOwner {
        // Check if the protocol is registered in the registry
        require(
            bytes(registry.getProtocolName(protocolId)).length > 0,
            "Protocol not registered"
        );
        require(
            registry.hasAdapter(protocolId, address(_asset)),
            "No adapter for this asset"
        );

        // Add to active protocols through the registry
        registry.addActiveProtocol(protocolId);

        emit ProtocolAdded(protocolId);
    }

    /**
     * @dev Remove a protocol from active protocols
     * @param protocolId ID of the protocol to remove
     */
    function removeActiveProtocol(
        uint256 protocolId
    ) external override onlyOwner {
        // Withdraw all funds from this protocol first
        _withdrawAllFromProtocol(protocolId);

        // Remove from active protocols through the registry
        registry.removeActiveProtocol(protocolId);
        emit ProtocolRemoved(protocolId);
    }

    /**
     * @dev Replace an active protocol with another
     * @param oldProtocolId ID of the protocol to replace
     * @param newProtocolId ID of the new protocol
     */
    function replaceActiveProtocol(
        uint256 oldProtocolId,
        uint256 newProtocolId
    ) external override onlyOwner {
        // Check if the new protocol is registered in the registry
        require(
            bytes(registry.getProtocolName(newProtocolId)).length > 0,
            "New protocol not registered"
        );
        require(
            registry.hasAdapter(newProtocolId, address(_asset)),
            "No adapter for new protocol"
        );

        // Replace in the registry
        registry.replaceActiveProtocol(oldProtocolId, newProtocolId);

        emit ProtocolRemoved(oldProtocolId);
        emit ProtocolAdded(newProtocolId);
    }

    /**
     * @dev Calculate how many shares a user will receive for depositing assets
     * @param assets Amount of assets being deposited
     * @return shares Amount of shares to be minted
     */
    function previewDeposit(
        uint256 assets
    ) public view override returns (uint256) {
        if (redemptionRate == 1e18) return assets; // 1:1 for first deposit
        return (assets * 1e18) / redemptionRate;
    }

    /**
     * @dev Calculate how many assets are needed to mint a specific number of shares
     * @param shares Amount of shares desired
     * @return assets Amount of assets needed
     */
    function previewMint(
        uint256 shares
    ) public view override returns (uint256) {
        if (redemptionRate == 1e18) return shares; // 1:1 for first deposit
        return (shares * redemptionRate) / 1e18;
    }

    /**
     * @dev Deposit assets into the vault
     * @param user Address of the user to deposit for
     * @param amount Amount of assets to deposit
     */
    function deposit(
        address user,
        uint256 amount
    ) external override nonReentrant {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Deposit must be > 0");

        // Get active protocols from registry
        uint256[] memory activeProtocolIds = registry.getActiveProtocolIds();
        require(activeProtocolIds.length > 0, "No active protocols");

        // Transfer assets from sender to this contract
        _asset.transferFrom(msg.sender, address(this), amount);

        // Distribute funds to protocols first
        _distributeAssets();

        // Calculate and mint receipt tokens after distribution
        uint256 receiptTokens = previewDeposit(amount);
        _mint(user, receiptTokens);

        emit Deposited(user, amount, block.timestamp);
    }

    /**
     * @dev Override of ERC4626 withdraw function
     * @param assets Amount of assets to withdraw
     * @param receiver Address receiving the assets
     * @param owner Address that owns the shares being burned
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

        // Check allowance and balance for the case where msg.sender != owner
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) {
                _approve(owner, msg.sender, allowed - assets);
            }
        }

        // Calculate shares to burn based on current redemption rate
        uint256 totalSupplyBefore = totalSupply();
        uint256 ownerBalanceBefore = balanceOf(owner);

        uint256 shares = convertToShares(assets);
        require(shares <= ownerBalanceBefore, "Insufficient shares");
        require(shares <= totalSupplyBefore, "Shares exceed total supply");

        // Withdraw funds from protocols first
        uint256 actualWithdrawnAmount = _withdrawFromProtocols(
            assets,
            receiver
        );
        require(actualWithdrawnAmount > 0, "Withdrawal failed");

        // Burn shares
        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return actualWithdrawnAmount;
    }

    /**
     * @dev Check and harvest yield from all protocols
     */
    function accrueAndFlush()
        external
        override
        onlyOwnerOrAuthorized
        returns (uint256 harvestedAmount)
    {
        uint256 totalAssets = _harvestAllProtocols();

        totalAssets += _asset.balanceOf(address(this));

        // Update redemption rate based on total assets
        previousRedemptionRate = redemptionRate; // Store previous rate

        // Check if there's any supply before calculating redemption rate
        uint256 currentSupply = totalSupply();
        if (currentSupply == 0) {
            redemptionRate = 1e18;
        } else {
            redemptionRate = (totalAssets * 1e18) / currentSupply;
        }

        // flush to combined vault
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
     * @dev Supply funds to a specific protocol
     * @param protocolId ID of the protocol to supply to
     * @param amount Amount to supply
     */
    function supplyToProtocol(
        uint256 protocolId,
        uint256 amount
    ) external override onlyOwnerOrAuthorized {
        require(amount > 0, "Amount must be greater than zero");

        IProtocolAdapter adapter = registry.getAdapter(
            protocolId,
            address(_asset)
        );
        require(address(adapter) != address(0), "Invalid protocol adapter");

        // Approve the protocol adapter to spend the vault's funds
        _asset.approve(address(adapter), amount);

        // Supply funds to the new protocol
        uint256 supplied = adapter.supply(address(_asset), amount);
        require(supplied > 0, "Supply failed");
    }

    /**
     * @dev Get the current redemption rate
     * @return Current redemption rate with 18 decimals precision
     */
    function getRedemptionRate() external view returns (uint256) {
        return redemptionRate;
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

            // Approve the protocol adapter to spend our funds
            _asset.approve(address(adapter), amountPerProtocol);

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

        // Distribute withdrawal evenly across all active protocols
        uint256 amountPerProtocol = amount / activeProtocolIds.length;
        uint256 totalWithdrawn = 0;

        for (uint i = 0; i < activeProtocolIds.length; i++) {
            totalWithdrawn += _withdrawFromSingleProtocol(
                activeProtocolIds[i], 
                amountPerProtocol, 
                user
            );
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
    function _withdrawAllFromProtocol(
        uint256 protocolId
    ) public onlyOwnerOrAuthorized {
        IProtocolAdapter adapter = registry.getAdapter(
            protocolId,
            address(_asset)
        );

        // Get protocol's receipt token
        address receiptToken = adapter.getReceiptToken(address(_asset));
        require(receiptToken != address(0), "Invalid receipt token");

        // Get current balance of receipt tokens
        uint256 balance = IERC20(receiptToken).balanceOf(address(this));

        if (balance > 0) {
            // Approve the adapter to transfer receipt tokens if needed
            IERC20(receiptToken).approve(address(adapter), balance);

            // Transfer receipt tokens to adapter
            IERC20(receiptToken).transfer(address(adapter), balance);

            // Withdraw all funds
            uint256 withdrawn = adapter.withdraw(address(_asset), balance);
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
            // Approve the adapter to spend all aTokens before harvesting
            address aToken = adapter.getReceiptToken(address(_asset));
            if (aToken != address(0)) {
                IERC20(aToken).approve(
                    address(adapter),
                    IERC20(aToken).balanceOf(address(this))
                );
            }
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
     * @return totalManagedAssets The total amount of assets managed by the vault
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

        return total + _asset.balanceOf(address(this));
    }

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided
     * @param assets Amount of assets to convert
     * @return shares Amount of shares
     */
    function convertToShares(
        uint256 assets
    ) public view override returns (uint256) {
        return previewDeposit(assets);
    }

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided
     * @param shares Amount of shares to convert
     * @return assets Amount of assets
     */
    function convertToAssets(
        uint256 shares
    ) public view override returns (uint256) {
        return previewMint(shares);
    }

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their redemption
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets that would be received
     */
    function previewRedeem(
        uint256 shares
    ) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    /**
     * @dev Mints shares to receiver by depositing assets
     * @param shares Amount of shares to mint
     * @param receiver Address of the receiver
     * @return assets Amount of assets deposited
     */
    function mint(
        uint256 shares,
        address receiver
    ) public override returns (uint256) {
        uint256 assets = previewMint(shares);
        deposit(assets, receiver);
        return assets;
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
    ) public override returns (uint256) {
        uint256 assets = previewRedeem(shares);
        withdraw(assets, receiver, owner);
        return assets;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
