// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol" ;
import "@openzeppelin/contracts/access/Ownable.sol" ;

contract BatchErc721 is Ownable{
    IERC721 public token ;
    constructor(address erc721) {
        token = IERC721(erc721) ;
    }

    function batchTransferOnOwner(address [] memory to, uint256 [][] memory tokenIds, address owner) external onlyOwner {
        for(uint256 i = 0; i < to.length; i++) {
            uint256 []memory tokenId = tokenIds[i] ;
            for(uint256 j = 0; j < tokenId.length; j++) {
                token.safeTransferFrom(owner, to[i], tokenId[j]) ;
            }
        }
    }

    function setToken(address tokenAddr) external onlyOwner {
        token = IERC721(tokenAddr) ;
    }
}
