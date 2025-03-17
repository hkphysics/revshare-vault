// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDeFiAdapter {
    struct MarketData {
        uint256 liquidity;
        uint256 availableToBorrow;
        uint256 collateralFactor; // Scaled by 1e18 (e.g., 50% = 5e17)
        uint256 liquidationThreshold;
        uint256 reserveFactor;
        uint256 variableBorrowRate;
        bytes protocolSpecific;
    }

    struct UserPosition {
        address[] suppliedTokens;
        uint256[] suppliedAmounts;
        address[] borrowedTokens;
        uint256[] borrowedAmounts;
        uint256 healthFactor; // Scaled by 1e18
        bytes protocolSpecific;
    }

    /// @notice Deposit assets as collateral
    /// @param token The address of the asset to supply
    /// @param amount The amount to supply
    /// @param params Additional protocol-specific parameters
    function supply(
        address token,
        uint256 amount,
        bytes calldata params
    ) external returns (bool);

    /// @notice Withdraw collateral assets
    /// @param token The address of the asset to withdraw
    /// @param amount The amount to withdraw
    /// @param params Additional protocol-specific parameters
    function withdraw(
        address token,
        uint256 amount,
        bytes calldata params
    ) external returns (bool);

    /// @notice Borrow assets from the protocol
    /// @param token The address of the asset to borrow
    /// @param amount The amount to borrow
    /// @param params Additional protocol-specific parameters
    function borrow(
        address token,
        uint256 amount,
        bytes calldata params
    ) external returns (bool);

    /// @notice Repay borrowed assets
    /// @param token The address of the asset to repay
    /// @param amount The amount to repay
    /// @param params Additional protocol-specific parameters
    function repay(
        address token,
        uint256 amount,
        bytes calldata params
    ) external returns (bool);

    /// @notice Get current user position data
    /// @param user The address of the user
    function getUserPosition(
        address user
    ) external returns (UserPosition memory);

    /// @notice Get current market data for a specific asset
    /// @param token The address of the asset
    function getMarketData(
        address token
    ) external view returns (MarketData memory);

    // Events
    event Supplied(address indexed user, address token, uint256 amount);
    event Withdrawn(address indexed user, address token, uint256 amount);
    event Borrowed(address indexed user, address token, uint256 amount);
    event Repaid(address indexed user, address token, uint256 amount);
}
