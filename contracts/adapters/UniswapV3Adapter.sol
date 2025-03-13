// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IDexAdapter } from "../interfaces/IDexAdapter.sol";

contract UniswapV3Adapter is IDexAdapter {
    using SafeERC20 for IERC20;
    ISwapRouter public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = ISwapRouter(_swapRouter);
    }

    /**
     * @dev Executes a token swap on Uniswap V3
     * @param tokenIn Address of the input token
     * @param tokenOut Address of the output token
     * @param amountIn Exact amount of input tokens to swap
     * @param minAmountOut Minimum amount of output tokens to receive
     * @param fee The pool fee tier (500 = 0.05%)
     * @param deadline Transaction deadline timestamp
     * @param data Encoded 1inch swap parameters (executor address and swap calldata)
     * @return amountOut Actual amount of output tokens received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24 fee,
        uint256 deadline,
        bytes calldata data
    ) external returns (uint256 amountOut) {
        // Transfer input tokens from vault to adapter
        require(
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn),
            "Transfer from failed"
        );

        // Approve Uniswap router to spend tokens
        IERC20(tokenIn).safeIncreaseAllowance(address(swapRouter), amountIn);

        // Configure swap parameters
        ISwapRouter.ExactInputSingleParams memory params = 
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: fee,
                recipient: msg.sender, // Send output directly to vault
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });

        // Execute swap
        amountOut = swapRouter.exactInputSingle(params);

        // Reset approval for security
        IERC20(tokenIn).approve(address(swapRouter), 0);
    }
}
