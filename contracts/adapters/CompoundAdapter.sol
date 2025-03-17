// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IDeFiAdapter.sol";

interface CToken {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function borrowBalanceCurrent(address account) external returns (uint);
    function exchangeRateStored() external view returns (uint);
    function underlying() external view returns (address);
    function totalBorrows() external view returns (uint);
    function totalReserves() external view returns (uint);
    function getCash() external view returns (uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
}

interface Comptroller {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
    function markets(address cToken) external view returns (bool, uint, bool);
    function getAssetsIn(address account) external view returns (address[] memory);
}

contract CompoundAdapter is IDeFiAdapter {
    using SafeERC20 for IERC20;

    address public immutable comptroller;
    mapping(address => address) public underlyingToCToken;
    mapping(address => address) public cTokenToUnderlying;

    constructor(address _comptroller, address[] memory _cTokens) {
        comptroller = _comptroller;
        for (uint i = 0; i < _cTokens.length; i++) {
            address cToken = _cTokens[i];
            address underlying = CToken(cToken).underlying();
            underlyingToCToken[underlying] = cToken;
            cTokenToUnderlying[cToken] = underlying;
        }
    }

    function supply(address token, uint256 amount, bytes calldata) 
        external override returns (bool) 
    {
        address cToken = underlyingToCToken[token];
        require(cToken != address(0), "Unsupported token");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeIncreaseAllowance(cToken, amount);
        
        require(CToken(cToken).mint(amount) == 0, "Mint failed");
        _enterMarketIfNeeded(cToken);
        
        emit Supplied(msg.sender, token, amount);
        return true;
    }

    function withdraw(address token, uint256 amount, bytes calldata) 
        external override returns (bool) 
    {
        address cToken = underlyingToCToken[token];
        require(cToken != address(0), "Unsupported token");
        
        uint redeemResult = CToken(cToken).redeemUnderlying(amount);
        require(redeemResult == 0, "Redeem failed");
        
        uint balance = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, balance);
        
        emit Withdrawn(msg.sender, token, balance);
        return true;
    }

    function borrow(address token, uint256 amount, bytes calldata) 
        external override returns (bool) 
    {
        address cToken = underlyingToCToken[token];
        require(cToken != address(0), "Unsupported token");
        
        (uint error, uint liquidity, ) = Comptroller(comptroller).getAccountLiquidity(msg.sender);
        require(error == 0 && liquidity >= amount, "Insufficient collateral");
        
        require(CToken(cToken).borrow(amount) == 0, "Borrow failed");
        IERC20(token).safeTransfer(msg.sender, amount);
        
        emit Borrowed(msg.sender, token, amount);
        return true;
    }

    function repay(address token, uint256 amount, bytes calldata) 
        external override returns (bool) 
    {
        address cToken = underlyingToCToken[token];
        require(cToken != address(0), "Unsupported token");
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).safeIncreaseAllowance(cToken, amount);
        
        require(CToken(cToken).repayBorrow(amount) == 0, "Repay failed");
        
        emit Repaid(msg.sender, token, amount);
        return true;
    }

    function getUserPosition(address user) 
        external override returns (UserPosition memory) 
    {
        address[] memory markets = Comptroller(comptroller).getAssetsIn(user);
        UserPosition memory position;
        
        position.suppliedTokens = new address[](markets.length);
        position.suppliedAmounts = new uint256[](markets.length);
        position. borrowedTokens = new address[](markets.length);
        position. borrowedAmounts = new uint256[](markets.length);
        
        for (uint i = 0; i < markets.length; i++) {
            address cToken = markets[i];
            address underlying = cTokenToUnderlying[cToken];
            uint exchangeRate = CToken(cToken).exchangeRateStored();
            
            position.suppliedTokens[i] = underlying;
            position.suppliedAmounts[i] = (IERC20(cToken).balanceOf(user) * exchangeRate) / 1e18;
            
            position. borrowedTokens[i] = underlying;
            position. borrowedAmounts[i] = CToken(cToken).borrowBalanceCurrent(user);
        }
        
        (, uint liquidity, uint shortfall) = Comptroller(comptroller).getAccountLiquidity(user);
        position.healthFactor = shortfall > 0 ? (liquidity * 1e18) / (liquidity + shortfall) : type(uint256).max;
        
        return position;
    }

    function getMarketData(address token) 
        external view override returns (MarketData memory) 
    {
        address cToken = underlyingToCToken[token];
        require(cToken != address(0), "Unsupported token");
        
        (bool isListed, uint collateralFactor, ) = Comptroller(comptroller).markets(cToken);
        require(isListed, "Market not listed");
        
        return MarketData({
            liquidity: CToken(cToken).getCash(),
            availableToBorrow: CToken(cToken).getCash(),
            collateralFactor: collateralFactor,
            liquidationThreshold: collateralFactor, // Compound uses single collateral factor
            reserveFactor: CToken(cToken).totalReserves(),
            variableBorrowRate: CToken(cToken).borrowRatePerBlock(),
            protocolSpecific: abi.encode(CToken(cToken).supplyRatePerBlock())
        });
    }

    function _enterMarketIfNeeded(address cToken) internal {
        address[] memory currentMarkets = Comptroller(comptroller).getAssetsIn(msg.sender);
        for (uint i = 0; i < currentMarkets.length; i++) {
            if (currentMarkets[i] == cToken) return;
        }
        
        address[] memory marketsToEnter = new address[](1);
        marketsToEnter[0] = cToken;
        Comptroller(comptroller).enterMarkets(marketsToEnter);
    }
}
