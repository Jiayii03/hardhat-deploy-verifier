// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IProtocolAdapter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// LayerBank interfaces
interface IGToken is IERC20 {
    // Try different redeem functions based on common lending protocols
    function redeem(uint redeemTokens) external returns (uint);

    function redeemUnderlying(uint redeemAmount) external returns (uint);

    function exchangeRate() external view returns (uint256);

    function accruedExchangeRate() external returns (uint256);
}

interface ILayerBankCore {
    function enterMarkets(address[] calldata gTokens) external;

    function supply(
        address gToken,
        uint256 underlyingAmount
    ) external payable returns (uint256);

    function redeem(address gToken, uint256 amount) external returns (uint256);

    function redeemUnderlying(
        address gToken,
        uint256 amount
    ) external returns (uint256);
}

// Interfaces for rewards claiming and token swapping (for future implementations)
interface ILayerBankRewards {
    function claimReward(
        address[] calldata gTokens,
        address to
    ) external returns (uint256);
}

// Price calculator interface based on LayerBank
interface IPriceCalculator {
    function priceOf(address asset) external view returns (uint256 priceInUSD);
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

// Add these minimal interfaces at the top of your contract
interface ILTokenMinimal {
    function getCash() external view returns (uint256);

    function totalBorrow() external view returns (uint256);

    function totalReserve() external view returns (uint256);

    function reserveFactor() external view returns (uint256);

    function getRateModel() external view returns (address);
}

interface IRateModelMinimal {
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) external view returns (uint256);
}

/**
 * @title LayerBankAdapter
 * @notice Adapter for interacting with LayerBank protocol with interest-based harvesting
 * @dev Handles both supply and redeem operations with proper error handling
 */
contract LayerBankAdapter is IProtocolAdapter, Initializable, OwnableUpgradeable {
    // LayerBank Core contract
    ILayerBankCore public core;

    // Optional contracts for reward token harvesting (may not be used on Scroll)
    ILayerBankRewards public rewardsController;
    IPriceCalculator public priceCalculator;
    ISyncSwapRouter public syncSwapRouter;

    // Mapping of asset address to gToken address
    mapping(address => address) public gTokens;

    // Supported assets
    mapping(address => bool) public supportedAssets;

    // Protocol name
    string private constant PROTOCOL_NAME = "LayerBank";

    // Fixed APY (4%)
    uint256 private constant FIXED_APY = 400;

    // Tracking initial deposits and exchange rates for profit calculation
    mapping(address => uint256) private initialDeposits;
    mapping(address => uint256) private lastExchangeRates;

    // Add tracking for total principal per asset
    mapping(address => uint256) public totalPrincipal;

    // Last harvest timestamp per asset
    mapping(address => uint256) public lastHarvestTimestamp;

    // Minimum reward amount to consider profitable after fees (per asset)
    mapping(address => uint256) public minRewardAmount;

    // Address of the reward token (usually LBR) - for future reward token implementations
    address public rewardToken;

    // WETH address for swap paths (for future reward token swaps)
    address public weth;

    // SyncSwap pool addresses for common pairs (for future reward token swaps)
    mapping(address => mapping(address => address)) public poolAddresses;

    // Events
    event Initialized(address indexed initializer);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializer function
     * @param _coreAddress The address of the LayerBank Core contract
     */
    function initialize(address _coreAddress) public initializer {
        require(_coreAddress != address(0), "Invalid core address");
        
        __Ownable_init(msg.sender);
        core = ILayerBankCore(_coreAddress);
        
        emit Initialized(msg.sender);
    }

    /**
     * @dev Set external contract addresses (optional for Scroll without rewards)
     * @param _rewardsController The address of LayerBank Rewards Controller
     * @param _priceCalculator The address of the price calculator
     * @param _syncSwapRouter The address of the SyncSwap router
     * @param _rewardToken The address of the reward token (LBR)
     * @param _weth The address of WETH
     */
    function setExternalContracts(
        address _rewardsController,
        address _priceCalculator,
        address _syncSwapRouter,
        address _rewardToken,
        address _weth
    ) external onlyOwner {
        rewardsController = ILayerBankRewards(_rewardsController);
        priceCalculator = IPriceCalculator(_priceCalculator);
        syncSwapRouter = ISyncSwapRouter(_syncSwapRouter);
        rewardToken = _rewardToken;
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
     * @dev Add a supported asset
     * @param asset The address of the asset to add
     * @param gToken The address of the corresponding gToken
     */
    function addSupportedAsset(
        address asset,
        address gToken
    ) external onlyOwner {
        require(asset != address(0), "Invalid asset address");
        require(gToken != address(0), "Invalid gToken address");

        gTokens[asset] = gToken;
        supportedAssets[asset] = true;

        // Enter the market for this gToken
        address[] memory marketsToEnter = new address[](1);
        marketsToEnter[0] = gToken;
        core.enterMarkets(marketsToEnter);

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
    ) external override onlyOwner {
        require(supportedAssets[asset], "Asset not supported");
        minRewardAmount[asset] = amount;
    }

    /**
     * @dev Supply assets to LayerBank
     * @param asset The address of the asset to supply
     * @param amount The amount of the asset to supply
     * @return The amount of underlying tokens that were actually supplied
     */
    function supply(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Transfer asset from sender to this contract
        IERC20(asset).transferFrom(msg.sender, address(this), amount);

        // Approve LayerBank to spend asset
        IERC20(asset).approve(gToken, amount);

        // Get initial gToken balance of adapter
        uint256 initialGTokenBalance = IERC20(gToken).balanceOf(address(this));

        // Supply asset to LayerBank
        try core.supply(gToken, amount) {
            // Success
        } catch {
            // If supply fails, return 0
            return 0;
        }

        // Calculate how many gTokens were received
        uint256 finalGTokenBalance = IERC20(gToken).balanceOf(address(this));
        uint256 gTokensReceived = finalGTokenBalance - initialGTokenBalance;

        // Transfer received gTokens to the original sender
        if (gTokensReceived > 0) {
            IERC20(gToken).transfer(msg.sender, gTokensReceived);
        }

        // Update total principal
        totalPrincipal[asset] += amount;

        return amount;
    }

    /**
     * @dev Withdraw assets from LayerBank
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @return The actual amount of underlying tokens withdrawn
     */
    function withdraw(
        address asset,
        uint256 amount
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Calculate max withdrawal based on total principal
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal
            ? maxWithdrawal
            : amount;

        // Get current exchange rate
        uint256 exchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            exchangeRate = rate;
        } catch {
            exchangeRate = 1e18; // Default to 1:1 if we can't get the exchange rate
        }

        // Calculate gToken amount to redeem
        uint256 gTokenAmount = (withdrawAmount * 1e18) / exchangeRate;

        // Check if vault has enough gTokens
        uint256 vaultGTokenBalance = IERC20(gToken).balanceOf(msg.sender);
        require(
            vaultGTokenBalance >= gTokenAmount,
            "Insufficient gToken balance"
        );

        // transfer gToken from vault to adapter
        IERC20(gToken).transferFrom(msg.sender, address(this), gTokenAmount);

        // Withdraw from LayerBank to this contract
        try core.redeemUnderlying(gToken, withdrawAmount) returns (uint256) {
            // Success
        } catch {
            // If redeemUnderlying fails, try redeem with calculated gToken amount
            try core.redeem(gToken, gTokenAmount) returns (uint256) {
                // Success
            } catch {
                return 0; // All withdrawal methods failed
            }
        }

        // Calculate actual amount withdrawn
        uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
        uint256 actualWithdrawn = assetBalanceAfter;

        // Update total principal
        if (actualWithdrawn <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= actualWithdrawn;
        } else {
            totalPrincipal[asset] = 0;
        }

        // Transfer withdrawn assets to vault
        IERC20(asset).transfer(msg.sender, actualWithdrawn);

        return actualWithdrawn;
    }

    /**
     * @dev Withdraw assets from LayerBank and send directly to user
     * @param asset The address of the asset to withdraw
     * @param amount The amount of the asset to withdraw (in underlying tokens)
     * @param user The address to receive the withdrawn assets
     * @return The actual amount of underlying tokens withdrawn
     */
    function withdrawToUser(
        address asset,
        uint256 amount,
        address user
    ) external override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(user != address(0), "Invalid user address");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Calculate max withdrawal based on total principal
        uint256 maxWithdrawal = totalPrincipal[asset];
        uint256 withdrawAmount = amount > maxWithdrawal
            ? maxWithdrawal
            : amount;

        // Get current exchange rate
        uint256 exchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            exchangeRate = rate;
        } catch {
            exchangeRate = 1e18; // Default to 1:1 if we can't get the exchange rate
        }

        // Calculate gToken amount to redeem
        uint256 gTokenAmount = (withdrawAmount * 1e18) / exchangeRate;

        // Check if vault has enough gTokens
        uint256 vaultGTokenBalance = IERC20(gToken).balanceOf(msg.sender);
        require(
            vaultGTokenBalance >= gTokenAmount,
            "Insufficient gToken balance"
        );

        // transfer gToken from vault to adapter
        IERC20(gToken).transferFrom(msg.sender, address(this), gTokenAmount);

        // Withdraw directly to user using redeemUnderlying
        try core.redeemUnderlying(gToken, withdrawAmount) returns (uint256) {
            // Success
        } catch {
            // If redeemUnderlying fails, try redeem with calculated gToken amount
            try core.redeem(gToken, gTokenAmount) returns (uint256) {
                // Success
            } catch {
                return 0; // All withdrawal methods failed
            }
        }

        // Calculate actual amount received
        uint256 assetBalanceAfter = IERC20(asset).balanceOf(address(this));
        uint256 actualWithdrawn = assetBalanceAfter;

        // Update total principal
        if (actualWithdrawn <= totalPrincipal[asset]) {
            totalPrincipal[asset] -= actualWithdrawn;
        } else {
            totalPrincipal[asset] = 0;
        }

        // Transfer withdrawn assets to user
        IERC20(asset).transfer(user, actualWithdrawn);

        return actualWithdrawn;
    }

    /**
     * @dev Harvest yield from the protocol by compounding interest
     * @param asset The address of the asset
     * @return harvestedAmount The total amount harvested in asset terms
     */
    function harvest(
        address asset
    ) external override returns (uint256 harvestedAmount) {
        require(supportedAssets[asset], "Asset not supported");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Check if there's anything to harvest
        if (totalPrincipal[asset] == 0) {
            return 0; // Nothing to harvest
        }

        // Get current exchange rate
        uint256 exchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            exchangeRate = rate;
        } catch {
            return 0; // Can't get exchange rate
        }

        // Get vault's gToken balance
        uint256 gTokenBalance = IERC20(gToken).balanceOf(msg.sender);
        if (gTokenBalance == 0) {
            return 0;
        }

        // Calculate current value in underlying tokens
        uint256 currentValueInUnderlying = (gTokenBalance * exchangeRate) /
            1e18;

        // Calculate yield as the difference between current value and principal
        if (currentValueInUnderlying <= totalPrincipal[asset]) {
            return 0; // No yield to harvest
        }

        return currentValueInUnderlying;
    }

    /**
     * @dev Helper function to claim LayerBank rewards (called via try/catch to handle potential errors)
     * @param asset The address of the asset
     */
    function claimLayerBankRewards(address asset) external {
        require(msg.sender == address(this), "Only callable by self");
        require(
            address(rewardsController) != address(0),
            "Rewards controller not set"
        );

        address gToken = gTokens[asset];
        address[] memory gTokensArray = new address[](1);
        gTokensArray[0] = gToken;

        // Claim rewards (does nothing if no rewards are configured)
        rewardsController.claimReward(gTokensArray, address(this));
    }

    /**
     * @dev Get the current APY for an asset
     * @param asset The address of the asset
     * @return apyBps The current APY in basis points (1% = 100)
     */
    function getAPY(address asset) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // For LayerBank, we need to calculate the APY from the rate model
        try this.calculateLayerBankAPY(gToken) returns (uint256 apy) {
            return apy;
        } catch {
            // Fallback to fixed APY if calculation fails
            return FIXED_APY;
        }
    }

    /**
     * @dev Helper function to calculate LayerBank APY
     * @param gToken The address of the gToken
     * @return apyBps The APY in basis points
     */
    function calculateLayerBankAPY(
        address gToken
    ) external view returns (uint256 apyBps) {
        // This interface matches the minimum functions we need from ILToken
        ILTokenMinimal lToken = ILTokenMinimal(gToken);

        // Get the required parameters
        uint256 cash = lToken.getCash();
        uint256 borrows = lToken.totalBorrow();
        uint256 reserves = lToken.totalReserve();
        uint256 reserveFactor = lToken.reserveFactor();

        // Get the rate model address
        address rateModelAddress = lToken.getRateModel();
        IRateModelMinimal rateModel = IRateModelMinimal(rateModelAddress);

        // Calculate the supply rate
        uint256 perSecondSupplyRate = rateModel.getSupplyRate(
            cash,
            borrows,
            reserves,
            reserveFactor
        );

        // Convert to annual rate and then to basis points
        uint256 SECONDS_PER_YEAR = 31536000;
        uint256 annualSupplyRateFraction = perSecondSupplyRate *
            SECONDS_PER_YEAR;
        apyBps = (annualSupplyRateFraction * 10000) / 1e18;

        return apyBps;
    }

    /**
     * @dev Get the current balance in the protocol (in underlying asset terms)
     * @param asset The address of the asset
     * @return The current balance in underlying asset
     */
    function getBalance(
        address asset
    ) external view override returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Get the vault's gToken balance
        uint256 gTokenBalance = IERC20(gToken).balanceOf(msg.sender);

        // Get current exchange rate
        uint256 exchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            exchangeRate = rate;
        } catch {
            exchangeRate = 1e18; // Default to 1:1 if we can't get the exchange rate
        }

        // Convert gToken balance to underlying asset amount
        return (gTokenBalance * exchangeRate) / 1e18;
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
     * @dev Get total principal amount for this asset
     * @param asset The address of the asset
     * @return The total principal amount
     */
    function getTotalPrincipal(
        address asset
    ) external view override returns (uint256) {
        return totalPrincipal[asset];
    }

    /**
     * @dev Get the name of the protocol
     * @return The protocol name
     */
    function getProtocolName() external pure override returns (string memory) {
        return PROTOCOL_NAME;
    }

    /**
     * @dev Get the receipt token (gToken) for a specific asset
     * @param asset The address of the asset
     * @return The gToken address
     */
    function getReceiptToken(
        address asset
    ) external view override returns (address) {
        require(supportedAssets[asset], "Asset not supported");
        return gTokens[asset];
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
     * @dev Get current accrued interest (estimated)
     * @param asset The address of the asset
     * @return Estimated interest accrued since last harvest
     */
    function getEstimatedInterest(
        address asset
    ) external view returns (uint256) {
        require(supportedAssets[asset], "Asset not supported");

        address gToken = gTokens[asset];
        require(gToken != address(0), "gToken not found");

        // Get vault's gToken balance
        uint256 gTokenBalance = IERC20(gToken).balanceOf(msg.sender);
        if (gTokenBalance == 0) {
            return 0;
        }

        // Get current exchange rate
        uint256 currentExchangeRate;
        try IGToken(gToken).exchangeRate() returns (uint256 rate) {
            currentExchangeRate = rate;
        } catch {
            return 0; // Can't calculate interest without exchange rate
        }

        // Calculate current value in underlying tokens
        uint256 currentValueInUnderlying = (gTokenBalance *
            currentExchangeRate) / 1e18;

        // Calculate interest as difference between current value and total principal
        if (currentValueInUnderlying <= totalPrincipal[asset]) {
            return 0; // No interest accrued
        }

        return currentValueInUnderlying - totalPrincipal[asset];
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
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
