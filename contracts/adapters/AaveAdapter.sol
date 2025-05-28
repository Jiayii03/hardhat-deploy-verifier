// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title AaveAdapter
 * @notice Adapter contract for interacting with Aave V3 protocol
 * @dev This adapter handles deposits, withdrawals, and yield harvesting for Aave V3
 * 
 * Key Features:
 * - 1:1 asset to aToken conversion
 * - Automatic interest accrual
 * - Optional reward token harvesting
 * - Principal tracking with interest compounding
 * - Safety checks and balance verifications
 */

import "./interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// Simplified Aave interfaces
interface IAavePoolMinimal {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

// Adding IPool interface for getReserveData
interface IPool {
    function getReserveData(address asset) external view returns (DataTypes.ReserveDataLegacy memory);
}

library DataTypes {
    struct ReserveConfigurationMap {
        uint256 data;
    }

    struct ReserveDataLegacy {
        ReserveConfigurationMap configuration;
        uint128 liquidityIndex;
        uint128 currentLiquidityRate;
        uint128 variableBorrowIndex;
        uint128 currentVariableBorrowRate;
        uint128 currentStableBorrowRate;
        uint40 lastUpdateTimestamp;
        uint16 id;
        address aTokenAddress;
        address stableDebtTokenAddress;
        address variableDebtTokenAddress;
        address interestRateStrategyAddress;
        uint128 accruedToTreasury;
        uint128 unbacked;
        uint128 isolationModeTotalDebt;
    }
}

// Aave price oracle interface
interface IPriceOracleGetter {
    function getAssetPrice(address asset) external view returns (uint256);
    function BASE_CURRENCY_UNIT() external view returns (uint256);
}

// Aave rewards interface
interface IRewardsController {
    function claimAllRewards(
        address[] calldata assets,
        address to
    )
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}

// SyncSwap Router interface for future reward token swaps
interface ISyncSwapRouter {
    struct TokenInput {
        address token;
        uint amount;
    }

    // Swap function
    function swap(
        address[] calldata paths,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 deadline
    ) external returns (uint256 amountOut);
}

/**
 * @title AaveAdapter
 * @notice Adapter for interacting with Aave protocol with interest-based harvesting
 * @dev Implements the IProtocolAdapter interface
 */
contract AaveAdapter is IProtocolAdapter, Initializable, OwnableUpgradeable {
    // Core Aave contract for deposits and withdrawals
    IAavePoolMinimal public pool;

    // Address that can call harvest and other management functions
    address public authorizedCaller;

    // Optional contracts for reward token harvesting (may not be used on Scroll)
    IRewardsController public rewardsController;
    IPriceOracleGetter public priceOracle;
    ISyncSwapRouter public syncSwapRouter;

    // Maps underlying asset addresses to their corresponding aToken addresses
    mapping(address => address) public aTokens;

    // Tracks which assets are supported by this adapter
    mapping(address => bool) public supportedAssets;

    // Protocol identifier
    string private constant PROTOCOL_NAME = "Aave V3";

    // Tracks last harvest time per asset to calculate time-based metrics
    mapping(address => uint256) public lastHarvestTimestamp;

    // Minimum reward amount to consider profitable after fees (per asset)
    mapping(address => uint256) public minRewardAmount;

    // Tracks total principal per asset including compounded interest
    mapping(address => uint256) public totalPrincipal;

    // WETH address for swap paths (for future reward token swaps)
    address public weth;

    // SyncSwap pool addresses for common pairs (for future reward token swaps)
    mapping(address => mapping(address => address)) public poolAddresses;

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
     * @notice Initializes the adapter with Aave pool address
     * @dev Called during proxy deployment
     * @param _poolAddress The address of the Aave Pool contract
     */
    function initialize(address _poolAddress) public initializer {
        require(_poolAddress != address(0), "Invalid pool address");
        
        __Ownable_init(msg.sender);
        pool = IAavePoolMinimal(_poolAddress);
        
        emit Initialized(msg.sender);
    }

    /**
     * @notice Sets up external contract addresses for reward harvesting
     * @dev Optional setup for networks with Aave rewards
     * @param _rewardsController Aave's rewards controller
     * @param _priceOracle Aave's price oracle
     * @param _syncSwapRouter Router for swapping reward tokens
     * @param _weth WETH address for swap paths
     */
    function setExternalContracts(
        address _rewardsController,
        address _priceOracle,
        address _syncSwapRouter,
        address _weth
    ) external onlyOwner {
        rewardsController = IRewardsController(_rewardsController);
        priceOracle = IPriceOracleGetter(_priceOracle);
        syncSwapRouter = ISyncSwapRouter(_syncSwapRouter);
        weth = _weth;
    }

    /**
     * @dev Configure a pool for a token pair in SyncSwap (for future reward token swaps)
     * @param tokenA First token in the pair
     * @param tokenB Second token in the pair
     * @param poolAddress Address of the SyncSwap pool
     */
    function configurePool(
        address tokenA,
        address tokenB,
        address poolAddress
    ) external onlyOwner {
        require(
            tokenA != address(0) && tokenB != address(0),
            "Invalid token addresses"
        );
        require(poolAddress != address(0), "Invalid pool address");

        // Configure pool for both directions
        poolAddresses[tokenA][tokenB] = poolAddress;
        poolAddresses[tokenB][tokenA] = poolAddress;
    }

    /**
     * @notice Adds a new asset to the adapter
     * @dev Maps underlying asset to its aToken and sets default min reward amount
     * @param asset The underlying asset address
     * @param aToken The corresponding aToken address
     */
    function addSupportedAsset(
        address asset,
        address aToken
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(aToken != address(0), "Invalid aToken address");

        aTokens[asset] = aToken;
        supportedAssets[asset] = true;

        // Set default min reward amount (0.1 units)
        uint8 decimals = IERC20Metadata(asset).decimals();
        minRewardAmount[asset] = 1 * 10 ** (decimals - 1); // 0.1 units
    }

    /**
     * @dev Remove a supported asset
     * @param asset The address of the asset to remove
     */
    function removeSupportedAsset(address asset) external onlyOwner {
        supportedAssets[asset] = false;
    }

    /**
     * @dev Set the minimum reward amount to consider profitable after fees
     * @param asset The address of the asset
     * @param amount The minimum reward amount
     */
    function setMinRewardAmount(
        address asset,
        uint256 amount
    ) external override(IProtocolAdapter) onlyOwnerOrAuthorized {
        require(supportedAssets[asset], "Asset not supported");
        minRewardAmount[asset] = amount;
    }

    /**
     * @notice Supplies assets to Aave protocol
     * @dev Handles asset transfer, approval, and supply to Aave
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

        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");

        // Transfer and approve
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        totalPrincipal[asset] += amount;
        IERC20(asset).approve(address(pool), amount);

        // Supply to Aave
        pool.supply(asset, amount, msg.sender, 0);

        return amount;
    }

    /**
     * @notice Withdraws assets from Aave protocol
     * @dev Handles aToken transfer, withdrawal, and asset transfer back to vault
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

        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");

        // Calculate safe withdrawal amount
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal ? maxWithdrawal : amount;

        // Transfer aTokens and verify balance
        IERC20(aToken).transferFrom(msg.sender, address(this), withdrawAmount);
        uint256 aTokenBalance = IERC20(aToken).balanceOf(address(this));
        withdrawAmount = withdrawAmount > aTokenBalance ? aTokenBalance : withdrawAmount;

        if (withdrawAmount == 0) return 0;

        // Withdraw and verify
        uint256 assetBalanceBefore = IERC20(asset).balanceOf(address(this));
        pool.withdraw(asset, withdrawAmount, address(this));
        uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
        uint256 actualWithdrawn = assetBalanceAfter - assetBalanceBefore;

        // Update principal
        if(actualWithdrawn <= totalPrincipal[asset]){
            totalPrincipal[asset] -= actualWithdrawn;
        } else {
            totalPrincipal[asset] = 0;
        }

        // Transfer to vault
        IERC20(asset).transfer(msg.sender, actualWithdrawn);

        return actualWithdrawn;
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

        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");

        // Calculate the maximum amount that can be withdrawn
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal ? maxWithdrawal : amount;

        // Transfer aTokens from vault to adapter
        IERC20(aToken).transferFrom(msg.sender, address(this), withdrawAmount);

        // Get current aToken balance and apply safety check
        uint256 aTokenBalance = IERC20(aToken).balanceOf(address(this));
        withdrawAmount = withdrawAmount > aTokenBalance ? aTokenBalance : withdrawAmount;

        if (withdrawAmount == 0) {
            return 0;
        }

        // Get initial user balance
        uint256 userBalanceBefore = IERC20(asset).balanceOf(user);

        // Withdraw asset from Aave directly to the user
        pool.withdraw(asset, withdrawAmount, user);

        // Verify the withdrawal - calculate actual amount received
        uint256 userBalanceAfter = IERC20(asset).balanceOf(user);
        uint256 actualWithdrawn = userBalanceAfter - userBalanceBefore;

        // Update total principal
        if(actualWithdrawn <= totalPrincipal[asset]){
            totalPrincipal[asset] -= actualWithdrawn;
        } else {
            totalPrincipal[asset] = 0;
        }

        return actualWithdrawn;
    }

    /**
     * @dev Returns the calldata needed for the vault to approve the adapter to spend aTokens
     * @param asset The address of the underlying asset
     * @param amount The amount of aTokens to approve
     * @return target The target contract to call (the aToken address)
     * @return data The calldata for the approval function
     */
    function getApprovalCalldata(address asset, uint256 amount) external view returns (address target, bytes memory data) {
        require(supportedAssets[asset], "Asset not supported");
        
        // Get the aToken for this asset
        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");
        
        // For Aave's aTokens, we use the standard ERC20 approve function
        return (
            aToken, // Target is the aToken contract
            abi.encodeWithSignature("approve(address,uint256)", address(this), amount) // Standard approve calldata
        );
    }

    /**
     * @notice Harvests yield from Aave protocol
     * @dev Updates total principal and optionally claims rewards
     * @param asset The underlying asset address
     * @return totalAssets Total assets including accrued interest
     */
    function harvest(
        address asset
    ) external override(IProtocolAdapter) onlyOwnerOrAuthorized returns (uint256 totalAssets) {
        require(supportedAssets[asset], "Asset not supported");

        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");

        // Get total assets including interest
        totalAssets = IERC20(aToken).balanceOf(msg.sender);

        // Optional reward claiming
        if (address(rewardsController) != address(0)) {
            try this.claimAaveRewards(asset) {
                // Success
            } catch {
                // Ignore
            }
        }

        // Update tracking variables
        totalPrincipal[asset] = totalAssets;
        lastHarvestTimestamp[asset] = block.timestamp;

        return totalAssets;
    }

    /**
     * @dev Get total principal amount for this asset
     * @param asset The address of the asset
     * @return The total principal amount
     */
    function getTotalPrincipal(address asset) external view override(IProtocolAdapter) returns (uint256) {
        return totalPrincipal[asset];
    }

    /**
     * @dev Helper function to claim Aave rewards (called via try/catch to handle potential errors)
     * @param asset The address of the asset
     */
    function claimAaveRewards(address asset) external {
        require(msg.sender == address(this), "Only callable by self");
        require(
            address(rewardsController) != address(0),
            "Rewards controller not set"
        );

        address aToken = aTokens[asset];
        address[] memory assets = new address[](1);
        assets[0] = aToken;

        // Claim rewards (does nothing if no rewards are configured)
        rewardsController.claimAllRewards(assets, address(this));
    }

    /**
     * @notice Gets current APY for an asset
     * @dev Converts Aave's RAY units to basis points
     * @param asset The underlying asset address
     * @return APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override(IProtocolAdapter) returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        DataTypes.ReserveDataLegacy memory reserveData = IPool(address(pool))
            .getReserveData(asset);

        // Convert RAY (1e27) to basis points (1% = 100)
        uint256 ONE_RAY = 1e27;
        uint256 apyBps = (reserveData.currentLiquidityRate * 10000) / ONE_RAY;

        return apyBps;
    }

    /**
     * @dev Get the current balance in the protocol
     * @param asset The address of the asset
     * @return The total amount of underlying assets in the protocol
     */
    function getBalance(
        address asset
    ) external view override(IProtocolAdapter) returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        return totalPrincipal[asset];
    }

    /**
     * @dev Check if an asset is supported
     * @param asset The address of the asset
     * @return True if the asset is supported
     */
    function isAssetSupported(
        address asset
    ) external view override(IProtocolAdapter) returns (bool) {
        return supportedAssets[asset];
    }

    /**
     * @dev Get the name of the protocol
     * @return The protocol name
     */
    function getProtocolName() external pure override(IProtocolAdapter) returns (string memory) {
        return PROTOCOL_NAME;
    }

    /**
     * @dev Get the receipt token (aToken) for a specific asset
     * @param asset The address of the asset
     * @return The aToken address
     */
    function getReceiptToken(address asset) external view override(IProtocolAdapter) returns (address) {
        require(supportedAssets[asset], "Asset not supported");
        return aTokens[asset];
    }

    /**
     * @dev Get time since last harvest
     * @param asset The address of the asset
     * @return Time in seconds since last harvest (or 0 if never harvested)
     */
    function getTimeSinceLastHarvest(
        address asset
    ) external view returns (uint256) {
        if (lastHarvestTimestamp[asset] == 0) {
            return 0;
        }
        return block.timestamp - lastHarvestTimestamp[asset];
    }

    /**
     * @notice Gets estimated accrued interest
     * @dev Calculates interest based on Aave's liquidity index
     * @param asset The underlying asset address
     * @return Estimated interest amount
     */
    function getEstimatedInterest(
        address asset
    ) external view returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address aToken = aTokens[asset];
        require(aToken != address(0), "aToken not found");

        // Get current exchange rate
        DataTypes.ReserveDataLegacy memory reserveData = IPool(address(pool))
            .getReserveData(asset);
        uint256 exchangeRate = reserveData.liquidityIndex;
        
        // Calculate total value
        uint256 aTokenBalance = IERC20(aToken).balanceOf(msg.sender);
        uint256 totalValue = (aTokenBalance * exchangeRate) / 1e27;

        // Return interest as difference
        if (totalValue > totalPrincipal[asset]) {
            return totalValue - totalPrincipal[asset];
        }

        return 0;
    }

    /**
     * @dev Rescue tokens that are stuck in this contract
     * @param token The address of the token to rescue
     * @param to The address to send the tokens to
     * @param amount The amount of tokens to rescue
     */
    function rescueTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }

    /**
     * @dev Allows the owner to set an authorized caller
     * @param newCaller The new authorized caller address
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