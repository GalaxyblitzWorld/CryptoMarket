// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol" ;
import "@openzeppelin/contracts/token/ERC721/IERC721.sol" ;
import "../Manager/interfaces/IMintManager.sol";

contract BatchMint is Ownable {
    IMintManager public mintManager ;

    constructor(address mintManagerAddr) {
        mintManager = IMintManager(mintManagerAddr) ;
    }

    function batchMintNFT(address[] memory accounts, uint256[][] memory tokenIds, uint8 [] memory style, uint256 []memory cIndex, uint8[]memory kind) external onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            // (uint256 [] memory tokenIds, address owner, uint8 style, uint256 cIndex, KIND kind)
            bool isOk = mintManager.mintOfficial(tokenIds[i], accounts[i], style[i], cIndex[i], kind[i]) ;
            require(isOk, "mintOfficial fail") ;
        }
    }

    function batchSuitMintNFT(address[] memory account, uint256[][]memory sIds, uint256[][]memory dIds, uint256[][]memory hIds, uint8[] memory style, uint256[] memory cIndex) external onlyOwner {
        for(uint256 i = 0; i < account.length; i++) {
            //(uint256 [] memory sIds, uint256 [] memory dIds, uint256 [] memory hIds, address owner, uint8 style, uint256 cIndex)
            bool isOk = mintManager.mintSuitOfficial(sIds[i], dIds[i], hIds[i], account[i], style[i], cIndex[i]) ;
            require(isOk, "batchSuitMint fail") ;
        }
    }

    function setMintManager(address mintManagerAddr) external onlyOwner {
        mintManager = IMintManager(mintManagerAddr) ;
    }
}
