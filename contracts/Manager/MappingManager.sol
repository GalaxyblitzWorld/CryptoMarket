// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../MITNFT/IMITNft.sol";
import "../Common/BaseManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MappingManager is BaseManager, IERC721Receiver {
    // exchange tokenId => proj tokenId
    mapping(uint256 => uint256) public nftExToProj ;

    // proj tokenId => exchange tokenId
    mapping(uint256 => uint256) public nftProjToEx ;

    // nft init gens
    mapping(uint256 => uint256) public nftTokenGens ;

    // nft kind
    mapping(uint256 => KIND) public nftKindMap ;

    // proj nft contract addr
    IMITNft public Spaceship ;
    IMITNft public DefensiveFacility ;
    IMITNft public Hero ;

    // ex contract address
    IERC721 public exContract ;

    // kind
    enum KIND { NONE, SPACESHIP, HERO, DEFENSIVEFACILITY, SUIT }

    ////////////////////////////////////////////////////
    //              Event
    ////////////////////////////////////////////////////
    event SwapInEvent(uint256 srcTokenId, uint256 dstTokenId, uint256 gene, KIND kind, address owner) ;
    event SwapOutEvent(uint256 tokenId, uint256 bnTokenId, address owner) ;

    constructor(address sign, address SpaceshipAddr, address DefensiveFacilityAddr,
        address HeroAddr, address exAddr) BaseManager(sign, "MappingManager", "v1.0.0") {
        Spaceship = IMITNft(SpaceshipAddr) ;
        DefensiveFacility = IMITNft(DefensiveFacilityAddr) ;
        Hero = IMITNft(HeroAddr) ;
        exContract = IERC721(exAddr) ;
    }

    function swapIn(uint256 [] memory srcTokenIds, uint256 [] memory dstTokenIds, uint256 [] memory genes, KIND [] memory kinds, bytes memory signature) external whenNotPaused returns(bool) {
        require(srcTokenIds.length == dstTokenIds.length && dstTokenIds.length == genes.length && genes.length == kinds.length, "parameter exception!") ;
        checkSwapInSign(srcTokenIds, dstTokenIds, genes, kinds, signature) ;

        for(uint256 i = 0; i < srcTokenIds.length; i++) {
            exContract.safeTransferFrom(_msgSender(), address(this), srcTokenIds[i]) ;
            nftExToProj[srcTokenIds[i]] = dstTokenIds[i] ;
            nftTokenGens[srcTokenIds[i]] = genes[i] ;
            nftKindMap[srcTokenIds[i]] = kinds[i] ;
            nftProjToEx[dstTokenIds[i]] = srcTokenIds[i] ;

            if(kinds[i] == KIND.SPACESHIP) {
                bool isOk = Spaceship.mint( dstTokenIds[i], _msgSender()) ;
                require(isOk, "Mint Spaceship NFT Fail") ;
                isOk = Spaceship.setGens(genes[i], dstTokenIds[i]) ;
                require(isOk, "Init Spaceship NFT gene Fail") ;
            } else if(kinds[i] == KIND.DEFENSIVEFACILITY) {
                bool isOk = DefensiveFacility.mint( dstTokenIds[i], _msgSender()) ;
                require(isOk, "Mint DefensiveFacility NFT Fail") ;
                isOk = DefensiveFacility.setGens(genes[i], dstTokenIds[i]) ;
                require(isOk, "Init DefensiveFacility NFT gene Fail") ;
            } else if(kinds[i] == KIND.HERO) {
                bool isOk = Hero.mint( dstTokenIds[i], _msgSender()) ;
                require(isOk, "Mint Hero NFT Fail") ;
                isOk = Hero.setGens(genes[i], dstTokenIds[i]) ;
                require(isOk, "Init Hero NFT gene Fail") ;
            } else {
                require(false, "invalid nft type") ;
            }
            emit SwapInEvent(srcTokenIds[i], dstTokenIds[i], genes[i], kinds[i], _msgSender()) ;
        }

        return true ;
    }

    function swapOut(uint256 [] memory tokenIds) external whenNotPaused returns(bool){
        require(tokenIds.length > 0, "Convert NFT data cannot be empty!") ;

        for(uint256 i = 0; i < tokenIds.length ;i++ ){
            uint256 srcTokenId = nftProjToEx[tokenIds[i]] ;
            require(srcTokenId > 0, "The NFT to be converted does not exist") ;
            uint256 [] memory gens ;
            uint256 [] memory tIds = new uint256[](1) ;
            address [] memory owners ;
            tIds[0] = tokenIds[i] ;
            if(nftKindMap[srcTokenId] == KIND.SPACESHIP) {
                (gens,owners) = Spaceship.getNftOwnerGensByIds(tIds) ;
                require(gens.length > 0 && gens[0] > 0, "The Spaceship NFT to be converted does not exist") ;
                Spaceship.burn(tokenIds[i]) ;
            } else if(nftKindMap[srcTokenId] == KIND.DEFENSIVEFACILITY) {
                (gens,owners) = DefensiveFacility.getNftOwnerGensByIds(tIds) ;
                require(gens.length > 0 && gens[0] > 0, "The DEFENSIVEFACILITY NFT to be converted does not exist") ;
                DefensiveFacility.burn(tokenIds[i]) ;
            } else if(nftKindMap[srcTokenId] == KIND.HERO) {
                (gens,owners) = Hero.getNftOwnerGensByIds(tIds) ;
                require(gens.length > 0 && gens[0] > 0, "The HERO NFT to be converted does not exist") ;
                Hero.burn(tokenIds[i]) ;
            } else {
                require(false, "invalid nft type") ;
            }
            uint256 srcGens = nftTokenGens[srcTokenId] ;
            require(gens[0] == srcGens, "Upgraded NFTs cannot be exchanged back") ;
            require(owners[0] == _msgSender(), "The current NFT does not belong to you") ;

            // back
            exContract.safeTransferFrom(address(this), _msgSender(), srcTokenId) ;

            emit SwapOutEvent(tokenIds[i], srcTokenId, _msgSender()) ;
        }
        return true;
    }

    function checkSwapInSign(uint256 [] memory srcTokenIds, uint256 [] memory dstTokenIds,
        uint256 [] memory genes, KIND [] memory kinds, bytes memory signature) public view {
        // cal hash
        bytes memory encodeData = abi.encode(
            keccak256("SwapIn(uint256[] srcTokenIds,uint256[] dstTokenIds,uint256[] genes,uint8[] kinds,address owner)"),
            keccak256(abi.encodePacked(srcTokenIds)),
            keccak256(abi.encodePacked(dstTokenIds)),
            keccak256(abi.encodePacked(genes)),
            keccak256(abi.encodePacked(kinds)),
            _msgSender()
        ) ;
        (bool success,) = checkSign(encodeData, signature) ;
        require(success, "SwapIn: The operation of SwapIn permission is wrong!") ;
    }

    function updateAddr(address SpaceshipAddr, address DefensiveFacilityAddr, address HeroAddr, address exContractAddr) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Spaceship = IMITNft(SpaceshipAddr) ;
        DefensiveFacility = IMITNft(DefensiveFacilityAddr) ;
        Hero = IMITNft(HeroAddr) ;
        exContract = IERC721(exContractAddr) ;
    }

    function onERC721Received(address, address from, uint256, bytes calldata) external pure override returns (bytes4) {
        require(from != address(0x0));
        return IERC721Receiver.onERC721Received.selector;
    }

}
