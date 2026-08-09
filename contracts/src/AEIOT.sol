// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AEIOT — fixed-supply ERC-20 token on Base
/// @notice Total supply of 1,150,115 AEIOT is minted once to the deployer.
///         No mint, no burn, no owner — the supply can never change.
contract AEIOT {
    string public constant name = "AEIOT";
    string public constant symbol = "AEIOT";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_150_115 * 10 ** 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        return _transfer(msg.sender, to, value);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= value, "AEIOT: insufficient allowance");
            allowance[from][msg.sender] = allowed - value;
        }
        return _transfer(from, to, value);
    }

    function _transfer(address from, address to, uint256 value) private returns (bool) {
        require(to != address(0), "AEIOT: transfer to zero address");
        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= value, "AEIOT: insufficient balance");
        unchecked {
            balanceOf[from] = fromBalance - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
        return true;
    }
}
