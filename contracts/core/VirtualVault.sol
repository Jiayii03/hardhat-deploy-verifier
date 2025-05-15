// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface ICombinedVault {
    function deposit(address user, uint256 amount) external;
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

    // Queued user deposits for the current epoch, each user have only one entry
    struct QueuedDeposit {
        uint256 amount;
        bool exists;
    }
    mapping(address => QueuedDeposit) public queuedDeposits;
    address[] public queuedUsers;

    address public authorizedCaller;

    // Events
    event Initialized(address indexed initializer);

    modifier onlyOwnerOrAuthorized() {
        require(msg.sender == owner() || msg.sender == authorizedCaller, "Not authorized");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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

    function setAuthorizedCaller(address _caller) external onlyOwner {
        authorizedCaller = _caller;
    }

    function setCombinedVault(address _vault) external onlyOwner {
        require(_vault != address(0), "Invalid vault");
        combinedVault = ICombinedVault(_vault);
    }

    // Override deposit: 1:1 shares, queue user
    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        require(assets > 0, "Deposit must be > 0");
        // Transfer assets from user
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // Mint 1:1 shares
        shares = assets;
        _mint(receiver, shares);

        // Queue user deposit
        if (!queuedDeposits[receiver].exists) {
            queuedUsers.push(receiver);
            queuedDeposits[receiver].exists = true;
        }
        queuedDeposits[receiver].amount += assets;

        emit Deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    // Only allow withdrawal if funds are still queued
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256 shares) {
        require(queuedDeposits[owner].amount >= assets, "Not enough queued");
        shares = assets;
        _burn(owner, shares);

        queuedDeposits[owner].amount -= assets;
        if (queuedDeposits[owner].amount == 0) {
            queuedDeposits[owner].exists = false;
            _removeQueuedUser(owner);
        }

        IERC20(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
        return shares;
    }

    // Transfer all queued funds to the Combined Vault at epoch end
    function flushToCombinedVault() external onlyOwnerOrAuthorized nonReentrant {
        for (uint i = 0; i < queuedUsers.length; i++) {
            address user = queuedUsers[i];
            uint256 amount = queuedDeposits[user].amount;
            if (amount > 0) {
                // Approve and deposit to Combined Vault
                IERC20(asset()).forceApprove(address(combinedVault), amount);
                combinedVault.deposit(user, amount);
                // Burn user's virtual shares
                _burn(user, amount);
                // Reset queue
                queuedDeposits[user].amount = 0;
                queuedDeposits[user].exists = false;
            }
        }
        // Clear queuedUsers array (optional: optimize for gas)
        delete queuedUsers;
    }

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

    // Override previewDeposit, previewMint, etc. for 1:1 logic
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return assets;
    }
    function previewMint(uint256 shares) public view override returns (uint256) {
        return shares;
    }
    function convertToShares(uint256 assets) public view override returns (uint256) {
        return assets;
    }
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return shares;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
