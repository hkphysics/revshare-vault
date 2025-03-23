// SPDX-License-Identifier: BSD-2-Clause
// Copyright (C) 2025 AXC Technology

// Generated from gitbook documentation by DeepSeek r1

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RWAFiVault is ERC20Burnable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    
    struct TokenConfig {
        IERC20 token;
        uint256 weight;
    }
    
    TokenConfig[] public tokenConfigs;
    uint256 public divisor;
    IERC20 public axcToken;
    uint256 public performanceFee;
    
    mapping(address => mapping(IERC20 => uint256)) public escrowBalances;
    mapping(IERC20 => uint256) public totalEscrowBalance;

    event FeeCollected(uint256 amount);
    event PerformanceFeeUpdated(uint256 newFee);

    constructor(
        string memory name,
        string memory symbol,
        TokenConfig[] memory initialTokens,
        uint256 _divisor,
        IERC20 _axcToken,
        uint256 _performanceFee,
        address initialGovernor
    ) ERC20(name, symbol) {
        // Role initialization
        _grantRole(DEFAULT_ADMIN_ROLE, initialGovernor);
        _grantRole(GOVERNOR_ROLE, initialGovernor);
        _grantRole(MINTER_ROLE, initialGovernor);
        _grantRole(BURNER_ROLE, initialGovernor);
        
        // Role hierarchy setup
        _setRoleAdmin(MINTER_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(BURNER_ROLE, GOVERNOR_ROLE);
        _setRoleAdmin(GOVERNOR_ROLE, DEFAULT_ADMIN_ROLE);

        divisor = _divisor;
        axcToken = _axcToken;
        performanceFee = _performanceFee;
        
        for (uint256 i = 0; i < initialTokens.length; i++) {
            tokenConfigs.push(initialTokens[i]);
        }
    }

    function depositEscrow(IERC20 token, uint256 amount) external nonReentrant {
        token.safeTransferFrom(msg.sender, address(this), amount);
        escrowBalances[msg.sender][token] += amount;
	totalEscrowBalance[token] += amount;
    }

    function withdrawEscrow(IERC20 token, uint256 amount) external nonReentrant {
        require(escrowBalances[msg.sender][token] >= amount, "Insufficient escrow");
        escrowBalances[msg.sender][token] -= amount;
	totalEscrowBalance[token] -= amount;
        token.safeTransfer(msg.sender, amount);
    }

    function mint(address account, uint256 amount) public onlyRole(MINTER_ROLE) nonReentrant returns (bool){
        for (uint256 i = 0; i < tokenConfigs.length; i++) {
            TokenConfig memory config = tokenConfigs[i];
            uint256 requiredAmount = (amount * config.weight) / divisor;
            require(escrowBalances[msg.sender][config.token] >= requiredAmount, "Insufficient tokens");
            escrowBalances[msg.sender][config.token] -= requiredAmount;
        }
        _mint(account, amount);
	return true;
    }

    function burn(uint256 amount) public override onlyRole(BURNER_ROLE) nonReentrant {
        _burn(msg.sender, amount);
        
        for (uint256 i = 0; i < tokenConfigs.length; i++) {
            TokenConfig memory config = tokenConfigs[i];
            uint256 outputAmount = (amount * config.weight) / divisor;
            escrowBalances[msg.sender][config.token] += outputAmount;
        }
    }

    function burnFrom(address account, uint256 amount) public override onlyRole(BURNER_ROLE) nonReentrant {
        _burn(account, amount);
        for (uint256 i = 0; i < tokenConfigs.length; i++) {
            TokenConfig memory config = tokenConfigs[i];
            uint256 outputAmount = (amount * config.weight) / divisor;
            escrowBalances[account][config.token] += outputAmount;
        }
    }

    function setPerformanceFee(uint256 newFee) external onlyRole(GOVERNOR_ROLE) {
        performanceFee = newFee;
        emit PerformanceFeeUpdated(newFee);
    }

    function collectFees() external onlyRole(GOVERNOR_ROLE) {
        uint256 feeAmount = (totalSupply() * performanceFee) / 1e18;
        axcToken.safeTransfer(msg.sender, feeAmount);
        emit FeeCollected(feeAmount);
    }

    function flushToken(IERC20 token) external onlyRole(GOVERNOR_ROLE) {
        require(token != IERC20(address(this)), "Cannot flush vault token");
        uint256 balance = token.balanceOf(address(this)) - totalEscrowBalance[token];
        token.safeTransfer(msg.sender, balance);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
