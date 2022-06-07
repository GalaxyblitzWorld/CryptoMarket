// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol" ;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol" ;
contract BatchErc20 is Ownable{

    IERC20 public token ;

    constructor(address erc20) {
        token = IERC20(erc20) ;
    }

    function batchTransfer(address [] memory to, uint256 [] memory amount) external onlyOwner {
        for(uint256 i = 0 ; i < to.length; i++) {
            token.transfer(to[i], amount[i]) ;
        }
    }

    function withdraw()  external onlyOwner{
        uint256 balance = token.balanceOf(address(this)) ;
        if(balance > 0){
            token.transfer(_msgSender(), balance) ;
        }
    }
}
