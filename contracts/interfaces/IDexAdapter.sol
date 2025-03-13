// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDexAdapter {
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24 fee,
	uint256 deadline,
        bytes calldata data
    ) external returns (uint256 amountOut);
}
