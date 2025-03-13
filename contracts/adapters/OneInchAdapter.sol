// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDexAdapter } from "../interfaces/IDexAdapter.sol";

contract OneInchAdapter is IDexAdapter {
    using SafeERC20 for IERC20;
    
    address public immutable aggregationRouter;

    constructor(address _aggregationRouter) {
        aggregationRouter = _aggregationRouter;
    }

    /**
     * @dev Executes a token swap using 1inch aggregation router
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Exact amount of input tokens to swap
     * @param minAmountOut Minimum amount of output tokens to receive
     * @param data Encoded 1inch swap parameters (executor address and swap calldata)
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
	uint24,
	uint256,
        bytes calldata data
    ) external override returns (uint256 amountOut) {
        (address executor, bytes memory swapData) = abi.decode(data, (address, bytes));
        
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeIncreaseAllowance(aggregationRouter, amountIn);
	bytes memory swapDescription = abi.encode(
            IERC20(tokenIn),
            IERC20(tokenOut),
            msg.sender, // srcReceiver
            msg.sender, // dstReceiver
            amountIn,
            minAmountOut,
            0      // flags
        );

        (bool success, bytes memory result) = aggregationRouter.call(
            abi.encodeWithSelector(
                0x12aa3caf, // swap() selector
                executor,
                swapDescription,
                swapData
            )
        );
        
        require(success, "1inch swap failed");
        (amountOut,) = abi.decode(result, (uint256, uint256));
    }
}
