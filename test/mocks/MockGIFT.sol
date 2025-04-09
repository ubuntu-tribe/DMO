// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockGIFT is ERC20 {
    constructor(string memory name, string memory symbol, uint256 initialSupply) 
        ERC20(name, symbol) 
    {
        _mint(msg.sender, initialSupply);
    }
    
    function totalSupply() public view override returns (uint256) {
        return super.totalSupply();
    }
    
    function balanceOf(address account) public view override returns (uint256) {
        return super.balanceOf(account);
    }
    
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        return super.transfer(recipient, amount);
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }
}