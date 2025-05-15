// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./interfaces/IProtocolAdapter.sol";

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
    function getSupplyRate(uint utilization) external view returns (uint);
    
    // Account methods
    function accrueAccount(address account) external;
    function balanceOf(address owner) external view returns (uint256);
}

/**
 * @title ICometAllowance
 * @dev Interface for the allowance functions in Compound v3's Comet contracts
 */
interface ICometAllowance {
    /**
     * @dev Allows or disallows a manager to control msg.sender's account
     * @param manager The address to give or revoke privileges
     * @param isAllowed true to enable manager privileges, false to disable
     */
    function allow(address manager, bool isAllowed) external;
    
    /**
     * @dev Checks if an account has allowance to manage another account
     * @param owner The account owner
     * @param manager The account manager to check
     * @return True if manager is allowed to manage owner's account
     */
    function isAllowed(address owner, address manager) external view returns (bool);
}

/**
 * @title CompoundAdapter
 * @notice Adapter for interacting with Compound v3 (Comet)
 * @dev Implements the IProtocolAdapter interface
 */
contract CompoundAdapter is
    IProtocolAdapter,
    Initializable,
    OwnableUpgradeable
{
    // Reference to the Comet contract (Compound v3 instance)
    CometMainInterface public comet;

    // Mapping of asset address to cToken address
    mapping(address => address) public cTokens;

    // Mapping of supported assets
    mapping(address => bool) public supportedAssets;

    // Tracking total principal per asset
    mapping(address => uint256) public totalPrincipal;

    // Minimum reward threshold per asset
    mapping(address => uint256) public minRewardAmount;

    // Protocol name
    string private constant PROTOCOL_NAME = "Compound V3";

    // Events
    event Initialized(address indexed initializer);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializer function
     * @param _cometAddress The address of the Comet contract
     */
    function initialize(address _cometAddress) public initializer {
        require(_cometAddress != address(0), "Invalid Comet address");

        __Ownable_init(msg.sender);
        comet = CometMainInterface(_cometAddress);

        emit Initialized(msg.sender);
    }

    /**
     * @dev Add a supported asset
     * @param asset The address of the asset
     */
    function addSupportedAsset(
        address asset,
        address cToken
    ) external onlyOwner {
        supportedAssets[asset] = true;
        cTokens[asset] = cToken;
    }

    /**
     * @dev Remove a supported asset
     * @param asset The address of the asset
     */
    function removeSupportedAsset(address asset) external onlyOwner {
        supportedAssets[asset] = false;
    }

    /**
     * @dev Check if an asset is supported
     * @param asset The address of the asset
     * @return True if the asset is supported
     */
    function isAssetSupported(
        address asset
    ) external view override returns (bool) {
        return supportedAssets[asset];
    }

    /**
     * @dev Supply assets to Compound
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of underlying tokens that were successfully supplied
     */
    function supply(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Approve Comet contract to spend asset
        IERC20(asset).approve(address(comet), amount);

        // Supply base token or collateral to the vault's address
        comet.supplyTo(msg.sender, asset, amount);
        // Update total principal
        totalPrincipal[asset] += amount;

        return amount;
    }

    /**
     * @dev Withdraw assets from Compound
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @return The actual amount withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        // Calculate max withdrawal amount (total principal)
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal
            ? maxWithdrawal
            : amount;

        // No need to transfer cTokens - just withdraw directly from Comet
        comet.withdrawFrom(msg.sender, msg.sender, asset, withdrawAmount);

        // Update total principal
        if (withdrawAmount <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= withdrawAmount;
        } else {
            totalPrincipal[asset] = 0;
        }

        return withdrawAmount;
    }

    /**
     * @dev Withdraw assets from Compound and send directly to a user
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw
     * @param user The address of the user to receive the withdrawn assets
     * @return The amount of underlying tokens successfully withdrawn and sent to the user
     */
    function withdrawToUser(
        address asset,
        uint256 amount,
        address user
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(user != address(0), "Invalid user address");

        // Calculate max withdrawal amount (total principal)
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal
            ? maxWithdrawal
            : amount;

        // Get initial user balance
        uint256 userBalanceBefore = IERC20(asset).balanceOf(user);

        // Withdraw from Comet directly to user
        comet.withdrawFrom(msg.sender, user, asset, withdrawAmount);

        // Verify the withdrawal - calculate actual amount received
        uint256 userBalanceAfter = IERC20(asset).balanceOf(user);
        uint256 actualReceived = userBalanceAfter - userBalanceBefore;

        // Update total principal
        if (actualReceived <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= actualReceived;
        } else {
            totalPrincipal[asset] = 0;
        }

        return actualReceived;
    }

    function getApprovalCalldata(
        address asset,
        uint256 amount
    ) external view override returns (address target, bytes memory data) {
        require(supportedAssets[asset], "Asset not supported");

        // For Compound v3 (Comet), approval is handled by the allow function on the pool contract
        // The amount parameter is ignored because Compound's allow is a boolean flag

        // Return the Compound pool address and the allow function calldata
        return (
            address(comet), // Target is the Compound pool contract
            abi.encodeWithSelector(
                ICometAllowance.allow.selector,
                address(this),
                true
            ) 
        );
    }

    /**
     * @dev Get the total principal amount deposited in this protocol
     * @param asset The address of the asset
     * @return The total principal amount in underlying asset units
     */
    function getTotalPrincipal(
        address asset
    ) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return totalPrincipal[asset];
    }

    /**
     * @dev Get the current APY for an asset (directly from Compound)
     * @param asset The address of the asset
     * @return The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        uint utilization = comet.getUtilization();
        return comet.getSupplyRate(utilization);
    }

    /**
     * @dev Get the current balance in the protocol
     * @param asset The address of the asset
     * @return The current balance
     */
    function getBalance(
        address asset
    ) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return totalPrincipal[asset];
    }

    /**
     * @dev Harvest accrued interest from Compound
     * @param asset The address of the asset
     * @return totalAssets The total amount of underlying assets in the protocol
     */
    function harvest(
        address asset
    ) external override returns (uint256 totalAssets) {
        require(supportedAssets[asset], "Asset not supported");

        // Check if there's anything to harvest
        if (totalPrincipal[asset] == 0) {
            return 0; // Nothing to harvest
        }

        // Accrue interest for the user (Compound v3 requires this explicit call)
        comet.accrueAccount(msg.sender);

        // Get the current balance of the vault in Compound (including accrued interest)
        totalAssets = comet.balanceOf(msg.sender);
        
        // Update total principal with the current balance including interest
        totalPrincipal[asset] = totalAssets;

        return totalAssets;
    }

    /**
     * @dev Set the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @param amount The minimum reward amount
     */
    function setMinRewardAmount(
        address asset,
        uint256 amount
    ) external override {
        require(supportedAssets[asset], "Asset not supported");
        minRewardAmount[asset] = amount;
    }

    /**
     * @dev Get the estimated interest for an asset
     * @param asset The address of the asset
     * @return The estimated interest amount
     */
    function getEstimatedInterest(
        address asset
    ) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        uint utilization = comet.getUtilization();
        uint interestRate = comet.getSupplyRate(utilization);

        uint balance = comet.balanceOf(msg.sender);

        // Calculate estimated interest: (balance * rate) / scaling factor
        return (balance * interestRate) / 1e18;
    }

    /**
     * @dev Get the name of the protocol
     * @return The protocol name
     */
    function getProtocolName() external pure override returns (string memory) {
        return PROTOCOL_NAME;
    }

    /**
     * @dev Get the receipt token for a specific asset
     * @param asset The address of the asset
     * @return The Comet contract address as the receipt token
     * @notice In Compound V3, the Comet contract itself acts as the receipt token
     */
    function getReceiptToken(
        address asset
    ) external view override returns (address) {
        require(supportedAssets[asset], "Asset not supported");
        return address(comet);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
