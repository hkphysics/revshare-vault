// SPDX-License-Identifier: BSD-2-Clause
// Copyright (C) 2025 AXC Technology

// Generated from gitbook documentation by DeepSeek r1

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RWAFiVault is ERC20, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant BUNDLER_ROLE = keccak256("BUNDLER_ROLE");
    
    struct TokenConfig {
        IERC20 token;
        uint256 weight;
    }
    
    TokenConfig[] public tokenConfigs;
    uint256 public divisor;
    IERC20 public axcToken;
    uint256 public performanceFee;
    
    mapping(address => mapping(IERC20 => uint256)) public escrowBalances;

    event Bundled(address indexed user, uint256 amount);
    event Unbundled(address indexed user, uint256 amount);
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
        _grantRole(BUNDLER_ROLE, initialGovernor);
        
        // Role hierarchy setup
        _setRoleAdmin(BUNDLER_ROLE, GOVERNOR_ROLE);
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
    }

    function withdrawEscrow(IERC20 token, uint256 amount) external nonReentrant {
        require(escrowBalances[msg.sender][token] >= amount, "Insufficient escrow");
        escrowBalances[msg.sender][token] -= amount;
        token.safeTransfer(msg.sender, amount);
    }

    function bundle(uint256 amount) external onlyRole(BUNDLER_ROLE) nonReentrant {
        for (uint256 i = 0; i < tokenConfigs.length; i++) {
            TokenConfig memory config = tokenConfigs[i];
            uint256 requiredAmount = (amount * config.weight) / divisor;
            require(escrowBalances[msg.sender][config.token] >= requiredAmount, "Insufficient tokens");
            escrowBalances[msg.sender][config.token] -= requiredAmount;
        }
        _mint(msg.sender, amount);
        emit Bundled(msg.sender, amount);
    }

    function unbundle(uint256 amount) external onlyRole(BUNDLER_ROLE) nonReentrant {
        _burn(msg.sender, amount);
        
        for (uint256 i = 0; i < tokenConfigs.length; i++) {
            TokenConfig memory config = tokenConfigs[i];
            uint256 outputAmount = (amount * config.weight) / divisor;
            escrowBalances[msg.sender][config.token] += outputAmount;
        }
        emit Unbundled(msg.sender, amount);
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
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(msg.sender, balance);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
