// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol" ;
import "@openzeppelin/contracts/security/Pausable.sol" ;
import "../MITNFT/IMITNft.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol" ;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol" ;
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol" ;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol" ;

contract NFTGameSwap is AccessControl, Pausable, ReentrancyGuard, EIP712, IERC721Receiver {

    bytes32 public constant SIGN_ROLE = keccak256("SIGN_ROLE");
    enum KIND { NONE, SPACESHIP, HERO, DEFENSIVEFACILITY }

    IMITNft public immutable spaceship ;
    IMITNft public immutable hero ;
    IMITNft public immutable defensiveFacility ;

    // hero => (tokenId => owner)
    mapping(KIND => mapping(uint256 => address)) public nftToAccount;
    mapping(uint256 => KIND) public nftKinds ;

    // struct
    struct Nft {
        KIND kind;
        uint256 tokenId ;
    }

    bool public openTest = false ;
    address public signAddr ;

    /////////////////////////////////////////////////
    //                  events
    /////////////////////////////////////////////////
    event NftSwapInEvent(address account, Nft [] nfts) ;
    event NftSwapOutEvent(address account, Nft [] nfts, uint256 orderNum) ;

    constructor(address spaceshipAddr, address heroAddr, address defensiveFacilityAddr, address sign) EIP712("NFTGameSwap", "v1.0.0") {
        spaceship = IMITNft(spaceshipAddr) ;
        hero = IMITNft(heroAddr) ;
        defensiveFacility = IMITNft(defensiveFacilityAddr) ;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        signAddr = sign ;
    }

    // chain => game
    function nftSwapIn(Nft [] memory nfts) external nonReentrant whenNotPaused {
        require(nfts.length > 0, "The number of swapIn NFTs cannot be empty") ;
        for(uint256 i = 0 ; i < nfts.length; i++) {
            transferNft(nfts[i].kind, _msgSender(), address (this), nfts[i].tokenId) ;
            nftToAccount[nfts[i].kind][nfts[i].tokenId] = _msgSender() ;
            nftKinds[nfts[i].tokenId] = nfts[i].kind ;
        }
        emit NftSwapInEvent(_msgSender(), nfts) ;
    }

    function nftSwapOut(uint256[] memory tokenIds, uint256 orderNum, bytes memory signature) external nonReentrant whenNotPaused {
        require(tokenIds.length > 0, "The number of swapOut NFTs cannot be empty") ;
        checkNftSwapOutSign(tokenIds, orderNum, signature) ;
        _swapOut(tokenIds, orderNum) ;
    }

    // game => chain
    function nftSwapOut2(uint256[] memory tokenIds) external nonReentrant whenNotPaused {
        require(openTest, "test not started") ;
        require(tokenIds.length > 0, "The number of swapOut NFTs cannot be empty") ;
        _swapOut(tokenIds, 0) ;
    }

    function _swapOut(uint256[] memory tokenIds, uint256 orderNum) private {
        Nft [] memory nfts = new Nft[](tokenIds.length) ;
        for(uint256 i = 0; i < tokenIds.length; i++) {
            KIND kind = nftKinds[tokenIds[i]] ;
            require(nftToAccount[kind][tokenIds[i]] == _msgSender(), "There is an error in your permutation of the NFT") ;
            transferNft(kind, address (this), _msgSender(), tokenIds[i]) ;
            nfts[i] = Nft({ kind: kind, tokenId: tokenIds[i] }) ;
            delete nftToAccount[kind][tokenIds[i]];
            delete nftKinds[tokenIds[i]];
        }
        emit NftSwapOutEvent(_msgSender(), nfts, orderNum) ;
    }

    // transfer
    function transferNft(KIND kind, address from, address to, uint256 tId) private {
        if(kind == KIND.SPACESHIP) {
            spaceship.safeTransferFrom(from, to, tId) ;
        } else if(kind == KIND.HERO) {
            hero.safeTransferFrom(from, to, tId) ;
        } else if(kind == KIND.DEFENSIVEFACILITY) {
            defensiveFacility.safeTransferFrom(from, to, tId) ;
        } else {
            require(false, "Wrong type of replacement NFT") ;
        }
    }

    // check nft swap out sign
    function checkNftSwapOutSign(uint256[] memory tokenIds, uint256 orderNum, bytes memory signature) private view {
        // cal hash
        bytes memory encodeData = abi.encode(
            keccak256(abi.encodePacked("nftSwapOut(uint256[] tokenIds,address owner,uint256 orderNum)")),
            keccak256(abi.encodePacked(tokenIds)),
            _msgSender(),
            orderNum
        ) ;
        (address recovered, ECDSA.RecoverError error) = ECDSA.tryRecover(_hashTypedDataV4(keccak256(encodeData)), signature);
        require(error == ECDSA.RecoverError.NoError && recovered == signAddr, "Incorrect request signature") ;
    }

    function setOpenTest(bool open) external onlyRole(DEFAULT_ADMIN_ROLE) {
        openTest = open ;
    }

    function setSign(address sign) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signAddr = sign ;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause() ;
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause() ;
    }

    function onERC721Received(address, address from, uint256, bytes calldata) external pure override returns (bytes4) {
        require(from != address(0x0));
        return IERC721Receiver.onERC721Received.selector;
    }
}
