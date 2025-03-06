// contracts/GLDToken.sol
// SPDX-License-Identifier: BSD-2-Clause
pragma solidity ^0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";


/**

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

*/

/**

To distribute tokens, the user is checked against a white list if the user
passes, then the smart contract will check how many tokens are available in
the contract, and distribute those to the user

*/

contract RevShareToken is ERC20, AccessControl {
    struct UserPool {
        uint256 weightedAverage;
        uint256 lastCalc;
	uint256 tokensClaimed;
    }

    struct TotalPool {
        uint256 weightedAverage;
	uint256 tokensDistributed;
    }

    error AccessFailed();
    IERC20 public token;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant DISTRIBUTE_ROLE = keccak256("DISTRIBUTE_ROLE");
    bytes32 public constant CLAIM_ROLE = keccak256("CLAIM_ROLE");
    mapping(address => UserPool) public userPool;
    TotalPool public totalPool;

    constructor(address token_) ERC20("RevShare", "RBF") {
	token = IERC20(token_);
	_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address to, uint256 amount) public {
        if (!hasRole(MINTER_ROLE, msg.sender)) {
	    revert AccessFailed();
	}
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        if (!hasRole(BURNER_ROLE, msg.sender)) {
	    revert AccessFailed();
	}
        _burn(from, amount);
    }

    function _update(address from,  address to, uint256 value)  internal virtual override {
	super._update(from,  to,  value);
	_updateUserPool(from);
	_updateUserPool(to);
    }

    function _updateUserPool(address addr) internal virtual {
	if (addr == address(0)) {
	    return;
	}
	userPool[addr].weightedAverage += balanceOf(addr) * (
	    totalPool.tokensDistributed - userPool[addr].lastCalc
	);
	userPool[addr].lastCalc = totalPool.tokensDistributed;
    }

    function distribute(uint256 amount) public {
	if (!hasRole(DISTRIBUTE_ROLE, msg.sender)) {
	    revert AccessFailed();
	}
	totalPool.tokensDistributed += amount;
	totalPool.weightedAverage += totalSupply() * amount;
    }

    function claim() public {
        if (!hasRole(CLAIM_ROLE, msg.sender)) {
	    revert AccessFailed();
	}
	_updateUserPool(msg.sender);
	uint256 tokensToBeClaimed = userPool[msg.sender].weightedAverage *
	    totalPool.tokensDistributed / totalPool.weightedAverage -
	    userPool[msg.sender].tokensClaimed;
	if (tokensToBeClaimed >= token.balanceOf(address(this))) {
	    tokensToBeClaimed = token.balanceOf(address(this));
	}
	userPool[msg.sender].tokensClaimed += tokensToBeClaimed;
	token.transfer(msg.sender, tokensToBeClaimed);
    }
}
