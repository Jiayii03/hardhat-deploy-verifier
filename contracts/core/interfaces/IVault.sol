// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IVault
 * @notice Interface defining the required functions for the Vault contract
 * @dev Includes both ERC4626 and custom vault functionality
 */
interface IVault {
    /**
     * @dev Returns the address of the underlying token used for the Vault
     * @return The address of the underlying asset token
     */
    function asset() external view returns (address);

    /**
     * @dev Deposit assets into the vault (ERC4626-compatible)
     * @param assets Amount of assets to deposit
     * @param receiver Address receiving the shares
     * @return shares Amount of shares minted
     */
    function deposit(uint256 assets, address receiver) external returns (uint256);
    
    /**
     * @dev ERC4626-compatible withdraw function
     * @param assets Amount of assets to withdraw
     * @param receiver Address receiving the assets
     * @param owner Address that owns the shares being burned
     * @return Amount of assets withdrawn
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    
    /**
     * @dev Check and harvest yield from all protocols
     * @return totalAssets Total assets after harvesting
     */
    function accrueAndFlush() external returns (uint256 totalAssets);
    
    /**
     * @dev Get user balance 
     * @param account Address of the account
     * @return Balance of the account
     */
    function balanceOf(address account) external view returns (uint256);
    
    /**
     * @dev Add a protocol to active protocols
     * @param protocolId ID of the protocol to add
     */
    function addActiveProtocol(uint256 protocolId) external;
    
    /**
     * @dev Remove a protocol from active protocols
     * @param protocolId ID of the protocol to remove
     */
    function removeActiveProtocol(uint256 protocolId) external;
    
    /**
     * @dev Replace an active protocol with another
     * @param oldProtocolId ID of the protocol to replace
     * @param newProtocolId ID of the new protocol
     */
    function replaceActiveProtocol(uint256 oldProtocolId, uint256 newProtocolId) external;
    
    /**
     * @dev Get the current redemption rate
     * @return Current redemption rate with 18 decimals precision
     */
    function getRedemptionRate() external view returns (uint256);

    /**
     * @dev Get user's staked balance (excluding wallet balance)
     * @param user Address of the user
     * @return stakedBalance Amount of assets staked
     */
    function getUserStakedBalance(address user) external view returns (uint256);

    /**
     * @dev Get user's total balance including wallet
     * @param user Address of the user
     * @return totalBalance Total user balance
     */
    function getUserTotalBalance(address user) external view returns (uint256);

    /**
     * @dev Convert assets to shares
     * @param assets Amount of assets to convert
     * @return shares Amount of shares
     */
    function convertToShares(uint256 assets) external view returns (uint256);

    /**
     * @dev Convert shares to assets
     * @param shares Amount of shares to convert
     * @return assets Amount of assets
     */
    function convertToAssets(uint256 shares) external view returns (uint256);

    /**
     * @dev Preview deposit amount in shares
     * @param assets Amount of assets being deposited
     * @return shares Amount of shares to be minted
     */
    function previewDeposit(uint256 assets) external view returns (uint256);

    /**
     * @dev Preview mint amount in assets
     * @param shares Amount of shares desired
     * @return assets Amount of assets needed
     */
    function previewMint(uint256 shares) external view returns (uint256);

    /**
     * @dev Preview redeem amount in assets
     * @param shares Amount of shares to redeem
     * @return assets Amount of assets that would be received
     */
    function previewRedeem(uint256 shares) external view returns (uint256);

    /**
     * @dev Burn shares from owner and send assets to receiver
     * @param shares Amount of shares to redeem
     * @param receiver Address of the receiver
     * @param owner Address of the owner
     * @return assets Amount of assets withdrawn
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256);
}