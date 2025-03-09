// contracts/GLDToken.sol
// SPDX-License-Identifier: BSD-2-Clause
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";


/**
 * @title RevShareToken
 * @dev This contract distributes revenue to token holders using a modified MasterChef algorithm.

This token deals with two issues.

1) You need an algorithm that avoids looping over all account in order
to distribute tokens scalably

2) You don't want to hold all of the tokens in the contract, but
rather transfer tokens as needed


This is a RevShare contract that distributes revenue between token holders.

The contract has two features:

- it uses a variation of the MasterChef algorithm to distribute revenue between
different token holders.

The algorithm maintains a weighted average of the tokens distributed

   (weighted_average_total) = sum (tokens_distributed) * (total_tokens)

and a weighted average per user of the tokens distributed

   (weighted_average_user) = sum (tokens_distributed) * (user_tokens)

The total number of tokens which a user is entitied to is

   (total_user_tokens) = (weighted_average_user) / (weighted_average_total)
          * (total_tokens_distrbuted)

The number of tokens to be claimed is

   (user_tokens_claimed) = (total_user_tokens) - (user_tokens_received)

To distribute tokens, the user is checked against a white list if the user
passes, then the smart contract will check how many tokens are available in
the contract, and distribute those to the user

*/

contract RevShareToken is ERC20, AccessControl {
    using SafeERC20 for IERC20;
    struct UserPool {
        uint256 weightedAverage;
        uint256 lastCalc;
	uint256 tokensClaimed;
    }

    struct TotalPool {
        uint256 weightedAverage;
	uint256 tokensDistributed;
    }

    error ConstructorFailed();
    IERC20 public immutable TOKEN;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant DISTRIBUTE_ROLE = keccak256("DISTRIBUTE_ROLE");
    bytes32 public constant CLAIM_ROLE = keccak256("CLAIM_ROLE");
    mapping(address => UserPool) public userPool;
    TotalPool public totalPool;

    /**
     * @dev Constructor to initialize the contract and set the token address.
     * @param token_ Address of the token to be used for distribution.
     */
    constructor(address token_) ERC20("RevShare", "RBF") {
        if (token_ == address(0))
	    revert ConstructorFailed();
	TOKEN = IERC20(token_);
	_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Mints new tokens to a specified address.
     * @param to Address to which the tokens will be minted.
     * @param amount Amount of tokens to mint.
     * Requirements:
     * - Caller must have the MINTER_ROLE.
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from a specified address.
     * @param from Address from which the tokens will be burned.
     * @param amount Amount of tokens to burn.
     * Requirements:
     * - Caller must have the BURNER_ROLE.
     */
    function burn(address from, uint256 amount) public onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    /**
     * @dev Internal function to update user pools when tokens are transferred.
     * @param from Address from which tokens are being transferred.
     * @param to Address to which tokens are being transferred.
     * @param value Amount of tokens being transferred.
     */
    function _update(address from,  address to, uint256 value)  internal virtual override {
	_updateUserPool(from);
	_updateUserPool(to);
        super._update(from,  to,  value);
    }

    /**
     * @dev Internal function to update the user pool for a specific address.
     * @param addr Address of the user whose pool is being updated.
     */
    function _updateUserPool(address addr) internal {
	if (addr == address(0)) {
	    return;
	}
	userPool[addr].weightedAverage += balanceOf(addr) * (
	    totalPool.tokensDistributed - userPool[addr].lastCalc
	);
	userPool[addr].lastCalc = totalPool.tokensDistributed;
    }

    /**
     * @dev Distributes a specified amount of tokens to the total pool.
     * @param amount Amount of tokens to distribute.
     * Requirements:
     * - Caller must have the DISTRIBUTE_ROLE.
     */
    function distribute(uint256 amount) public onlyRole(DISTRIBUTE_ROLE) {
	totalPool.tokensDistributed += amount;
	totalPool.weightedAverage += totalSupply() * amount;
    }

    /**
     * @dev Allows users to claim their tokens based on their share.
     * Requirements:
     * - Caller must have the CLAIM_ROLE.
     */
    function claim() public onlyRole(CLAIM_ROLE) {
        if ( totalPool.weightedAverage == 0 ) return;
	_updateUserPool(msg.sender);
	uint256 tokensToBeClaimed = userPool[msg.sender].weightedAverage *
	    totalPool.tokensDistributed / totalPool.weightedAverage -
	    userPool[msg.sender].tokensClaimed;
        tokensToBeClaimed = tokensToBeClaimed > TOKEN.balanceOf(address(this)) ?
	    TOKEN.balanceOf(address(this)) : tokensToBeClaimed;
	userPool[msg.sender].tokensClaimed += tokensToBeClaimed;
	TOKEN.safeTransfer(msg.sender, tokensToBeClaimed);
    }
}
