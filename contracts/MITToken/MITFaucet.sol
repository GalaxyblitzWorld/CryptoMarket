// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol" ;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol" ;

contract MITFaucet is Ownable {

    IERC20 public token ;

    uint256 public amount = 10000 ether;

    uint256 public timeSpace = 1 days ;

    mapping(address => uint256) public accountTime ;

    constructor(address mitAddr) {
        token = IERC20(mitAddr) ;
    }

    function setAmount(uint256 newAmount) external onlyOwner {
        amount = newAmount ;
    }

    function setTimespace(uint256 _timeSpace) external onlyOwner {
        timeSpace = _timeSpace ;
    }

    function faucet() external {
        require(block.timestamp - accountTime[_msgSender()] > timeSpace, "faucet too frequently") ;
        token.transfer(_msgSender(), amount) ;
        accountTime[_msgSender()] = block.timestamp ;
    }
}
