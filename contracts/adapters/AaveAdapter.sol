// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDeFiAdapter {
    struct UserPosition {
        address[] suppliedTokens;
        uint256[] suppliedAmounts;
        address[] borrowedTokens;
        uint256[] borrowedAmounts;
        uint256 healthFactor;
        bytes protocolSpecific;
    }

    struct MarketData {
        uint256 liquidity;
        uint256 availableToBorrow;
        uint256 collateralFactor;
        uint256 liquidationThreshold;
        uint256 reserveFactor;
        uint256 variableBorrowRate;
        bytes protocolSpecific;
    }

    function supply(address token, uint256 amount, bytes calldata params) external returns (bool);
    function withdraw(address token, uint256 amount, bytes calldata params) external returns (bool);
    function borrow(address token, uint256 amount, bytes calldata params) external returns (bool);
    function repay(address token, uint256 amount, bytes calldata params) external returns (bool);
    function getUserPosition(address user) external returns (UserPosition memory);
    function getMarketData(address token) external view returns (MarketData memory);

    event Supplied(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event Borrowed(address indexed user, address indexed token, uint256 amount);
    event Repaid(address indexed user, address indexed token, uint256 amount);
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IAaveProtocolDataProvider {
    struct UserReserveData {
        address underlyingAsset;
        uint256 currentATokenBalance;
        uint256 currentStableDebt;
        uint256 currentVariableDebt;
    }

    function getUserReserves(address user) external view returns (UserReserveData[] memory, UserReserveData[] memory);
    
    function getReserveData(address asset) external view returns (
        uint256 decimals,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor,
        bool usageAsCollateralEnabled,
        bool borrowingEnabled,
        bool stableBorrowRateEnabled,
        bool isActive,
        bool isFrozen
    );

    function getReserveTokensAddresses(address asset) external view returns (
        address aTokenAddress,
        address stableDebtTokenAddress,
        address variableDebtTokenAddress
    );
}

interface ILendingPool {
    function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 rateMode, address onBehalfOf) external returns (uint256);
    
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

contract AaveAdapter is IDeFiAdapter {
    ILendingPool public immutable lendingPool;
    IAaveProtocolDataProvider public immutable dataProvider;

    constructor(address _lendingPool, address _dataProvider) {
        lendingPool = ILendingPool(_lendingPool);
        dataProvider = IAaveProtocolDataProvider(_dataProvider);
    }

    function supply(address token, uint256 amount, bytes calldata) external returns (bool) {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(address(lendingPool), amount);
        lendingPool.deposit(token, amount, msg.sender, 0);
        emit Supplied(msg.sender, token, amount);
        return true;
    }

    function withdraw(address token, uint256 amount, bytes calldata) external returns (bool) {
        (address aToken,,) = dataProvider.getReserveTokensAddresses(token);
        IERC20(aToken).transferFrom(msg.sender, address(this), amount);
        IERC20(aToken).approve(address(lendingPool), amount);
        uint256 withdrawn = lendingPool.withdraw(token, amount, msg.sender);
        require(withdrawn == amount, "Withdrawal failed");
        emit Withdrawn(msg.sender, token, amount);
        return true;
    }

    function borrow(address token, uint256 amount, bytes calldata params) external returns (bool) {
        uint256 interestRateMode = params.length >= 32 ? abi.decode(params, (uint256)) : 2;
        lendingPool.borrow(token, amount, interestRateMode, 0, msg.sender);
        emit Borrowed(msg.sender, token, amount);
        return true;
    }

    function repay(address token, uint256 amount, bytes calldata params) external returns (bool) {
        uint256 interestRateMode = params.length >= 32 ? abi.decode(params, (uint256)) : 2;
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(address(lendingPool), amount);
        uint256 repaid = lendingPool.repay(token, amount, interestRateMode, msg.sender);
        require(repaid == amount, "Repayment failed");
        emit Repaid(msg.sender, token, amount);
        return true;
    }

    function getUserPosition(address user) external override returns (UserPosition memory) {
        (IAaveProtocolDataProvider.UserReserveData[] memory reserves,) = dataProvider.getUserReserves(user);
        address[] memory suppliedTokens = new address[](reserves.length);
        uint256[] memory suppliedAmounts = new uint256[](reserves.length);
        address[] memory borrowedTokens = new address[](reserves.length);
        uint256[] memory borrowedAmounts = new uint256[](reserves.length);
        
        uint256 suppliedCount;
        uint256 borrowedCount;

        for (uint i = 0; i < reserves.length; i++) {
            if (reserves[i].currentATokenBalance > 0) {
                suppliedTokens[suppliedCount] = reserves[i].underlyingAsset;
                suppliedAmounts[suppliedCount] = reserves[i].currentATokenBalance;
                suppliedCount++;
            }
            
            uint256 totalDebt = reserves[i].currentStableDebt + reserves[i].currentVariableDebt;
            if (totalDebt > 0) {
                borrowedTokens[borrowedCount] = reserves[i].underlyingAsset;
                borrowedAmounts[borrowedCount] = totalDebt;
                borrowedCount++;
            }
        }

        // Trim arrays
        assembly {
            mstore(suppliedTokens, suppliedCount)
            mstore(suppliedAmounts, suppliedCount)
            mstore(borrowedTokens, borrowedCount)
            mstore(borrowedAmounts, borrowedCount)
        }

        (, , , , , uint256 healthFactor) = lendingPool.getUserAccountData(user);

        return UserPosition(
            suppliedTokens,
            suppliedAmounts,
            borrowedTokens,
            borrowedAmounts,
            healthFactor,
            abi.encode(reserves)
        );
    }

    function getMarketData(address token) external view override returns (MarketData memory) {
        (,uint256 ltv, uint256 liquidationThreshold,,uint256 reserveFactor,,,,,) = dataProvider.getReserveData(token);
        (address aToken,,) = dataProvider.getReserveTokensAddresses(token);
        uint256 liquidity = IERC20(token).balanceOf(aToken);
        
        return MarketData(
            liquidity,
            liquidity,  // Simplified availableToBorrow (same as liquidity)
            ltv * 1e14, // Convert from basis points (1e4) to 1e18 scale
            liquidationThreshold * 1e14,
            reserveFactor * 1e14,
            0,
            abi.encode(0)
        );
    }
}
