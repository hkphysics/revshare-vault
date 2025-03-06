// contracts/GLDToken.sol
// SPDX-License-Identifier: BSD-2-Clause
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";


/*

This is a RevShare contract that distributes revenue between token holders.

The contract has two features:

- it uses a variation of the MasterChef algorithm to distribute revenue between
different token holders.
- it limits the amount of tokens distribute to the tokens held by the contract
*/


contract RevShareToken is ERC20, AccessControl {
    struct UserPool {
	uint256 poolSize;
	uint256 lastCalc;
	uint256 tokensClaimed;
    }

    struct TotalPool {
	uint256 poolSize;
	uint256 tokenDistributed;
    }

    error AccessFailed();
    IERC20 public token = IERC20(token_);
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant DISTRIBUTE_ROLE = keccak256("DISTRIBUTE_ROLE");
    mapping(address => UserPool) public userPool;
    TotalPool public totalPool;

    constructor(address token_) public ERC20("RevShare", "RBF") {
	token = token_;
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
	if (addr != address(0)) {
	    userPool[addr].poolSize += balanceOf(addr) * (
		total_pool.tokenDistributed - userPool[addr].lastCalc);
	    userPool[addr].lastCalc = total_pool.tokenDistributed;
	}
    }

    function distribute(uint256 amount) public {
	if (!hasRole(DISTRIBUTE_ROLE, msg.sender)) {
	    revert AccessFailed();
	}
	totalPool.tokenDistributed += amount;
	totalPool.poolSize += totalSupply() * amount;
    }

    function claim() public {
	_updateUserPool(msg.sender);
	uint256 tokensToBeClaimed = float(userPool[msg.sender]) / float(totalPool.poolSize) *
	    totalDistributed - tokensClaimed.userPool[msg.sender];
	if (tokensToBeClaimed >= token.balanceOf(this)) {
	    tokensToBeClaimed =  token.balanceOf(this);
	}
	userPool[msg.sender].tokensClaimed += tokensToBeClaimed;
	token.transfer(msg.sender, tokensToBeClaimed);
    }
}
