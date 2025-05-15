// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IVault
 * @notice Interface defining the required functions for the Vault contract
 */
interface IVault {
    /**
     * @dev Returns the address of the underlying token used for the Vault
     * @return The address of the underlying asset token
     */
    function asset() external view returns (address);

    /**
     * @dev Deposit assets into the vault
     * @param user Address of the user to deposit for
     * @param amount Amount of assets to deposit
     */
    function deposit(address user, uint256 amount) external;
    
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
     */
    function accrueAndFlush() external returns (uint256 totalAssets);
    
    /**
     * @dev Get user balance 
     * @param account Address of the account
     * @return Balance of the account
     */
    function balanceOf(address account) external view returns (uint256);
    
    /**
     * @dev Supply funds to a specific protocol
     * @param protocolId ID of the protocol to supply to
     * @param amount Amount to supply
     */
    function supplyToProtocol(uint256 protocolId, uint256 amount) external;
    
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
}