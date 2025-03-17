// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../interfaces/IDeFiAdapter.sol";

interface IMorpho {
    struct MarketPoolInfo {
        uint128 supplyPoolIndex;
        uint128 borrowPoolIndex;
        uint128 supplyP2PIndex;
        uint128 borrowP2PIndex;
    }

    function supply(address underlying, uint256 amount) external;
    function withdraw(address underlying, uint256 amount) external;
    function borrow(address underlying, uint256 amount) external;
    function repay(address underlying, uint256 amount) external;
    
    function getSupplyBalance(address underlying, address user) external view returns (uint256);
    function getBorrowBalance(address underlying, address user) external view returns (uint256);
    function getMarketPoolIndexes(address underlying) external view returns (MarketPoolInfo memory);
    
    function isClaimRewardsPaused() external view returns (bool);
    function marketPauseStatus(address underlying) external view returns (bool paused, bool supplyPaused, bool borrowPaused);
}

contract MorphoAdapter is IDeFiAdapter {
    IMorpho public immutable morpho;
    address public immutable rewardsController;
    
    constructor(address _morpho, address _rewardsController) {
        morpho = IMorpho(_morpho);
        rewardsController = _rewardsController;
    }

    function supply(address token, uint256 amount, bytes calldata) external returns (bool) {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(address(morpho), amount);
        morpho.supply(token, amount);
        emit Supplied(msg.sender, token, amount);
        return true;
    }

    function withdraw(address token, uint256 amount, bytes calldata) external returns (bool) {
        morpho.withdraw(token, amount);
        emit Withdrawn(msg.sender, token, amount);
        return true;
    }

    function borrow(address token, uint256 amount, bytes calldata) external returns (bool) {
        morpho.borrow(token, amount);
        emit Borrowed(msg.sender, token, amount);
        return true;
    }

    function repay(address token, uint256 amount, bytes calldata) external returns (bool) {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(address(morpho), amount);
        morpho.repay(token, amount);
        emit Repaid(msg.sender, token, amount);
        return true;
    }

    function getUserPosition(address user) external view returns (UserPosition memory) {
        // In production, you would iterate through all supported markets
        // This simplified version tracks a single market position
        address[] memory markets = new address[](1);
        markets[0] = address(this); // Should be replaced with actual market list
        
        address[] memory suppliedTokens = new address[](markets.length);
        uint256[] memory suppliedAmounts = new uint256[](markets.length);
        address[] memory borrowedTokens = new address[](markets.length);
        uint256[] memory borrowedAmounts = new uint256[](markets.length);

        for (uint i = 0; i < markets.length; i++) {
            address underlying = markets[i];
            suppliedTokens[i] = underlying;
            suppliedAmounts[i] = morpho.getSupplyBalance(underlying, user);
            borrowedTokens[i] = underlying;
            borrowedAmounts[i] = morpho.getBorrowBalance(underlying, user);
        }

        (, , , , , uint256 healthFactor) = getHealthFactor();

        return UserPosition(
            suppliedTokens,
            suppliedAmounts,
            borrowedTokens,
            borrowedAmounts,
            healthFactor,
            abi.encode(morpho.isClaimRewardsPaused())
        );
    }

    function getMarketData(address token) external view returns (MarketData memory) {
        (bool paused, bool supplyPaused, bool borrowPaused) = morpho.marketPauseStatus(token);
        IMorpho.MarketPoolInfo memory indexes = morpho.getMarketPoolIndexes(token);
        
        return MarketData(
            IERC20(token).balanceOf(address(morpho)),
            borrowPaused ? 0 : IERC20(token).balanceOf(address(morpho)),
            uint256(indexes.supplyP2PIndex),  // Collateral factor as P2P rate
            uint256(indexes.borrowP2PIndex),  // Liquidation threshold as borrow rate
            paused ? 1e18 : 0,                // Reserve factor as pause status
            uint256(indexes.borrowPoolIndex), // Variable borrow rate from pool
            abi.encode(supplyPaused, borrowPaused)
        );
    }

    function getHealthFactor() internal pure returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        // Simplified health factor calculation
        totalCollateralETH = 1e18;
        totalDebtETH = 0.5e18;
        healthFactor = (totalCollateralETH * 1e18) / totalDebtETH;
        return (totalCollateralETH, totalDebtETH, 0, 0, 0, healthFactor);
    }
}
