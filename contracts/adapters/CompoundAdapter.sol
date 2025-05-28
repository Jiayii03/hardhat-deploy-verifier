// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@compound/CometMainInterface.sol";
import "./interfaces/IProtocolAdapter.sol";

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
