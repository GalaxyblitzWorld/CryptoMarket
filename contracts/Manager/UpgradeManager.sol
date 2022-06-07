// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

///////////////////////////////////
//     MintETHManager Manager
///////////////////////////////////
import "../Common/BaseManager.sol";
import "../MITNFT/IMITNft.sol";
import "../Staking/IMITStakingNFT.sol" ;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol" ;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract UpgradeManager is BaseManager, IERC721Receiver {

    enum KIND { NONE, SPACESHIP, HERO, DEFENSIVEFACILITY, SUIT }

    // upgrade record
    struct UpgradeRecord {
        // account
        address account ;

        // NFT kind
        KIND kind ;

        // main NFT tokenId
        uint256 mainTokenId ;

        // main NFT gen
        uint256 mainGens ;

        // extra NFT tokenId
        uint256 extraTokenId ;

        // extra NFT gen
        uint256 extraGens ;

        // claim blockNo
        uint256 claimBlockNo ;

        // claim status (default: false)
        bool isClaimed ;
    }

    // UpgradeRecord
    UpgradeRecord [] public upgradeRecords ;

    // upgrade fee
    uint256 public upgradeFee = 6 ether;

    // Spaceship contract
    IMITNft public spaceship ;

    // DefensiveFacility contract
    IMITNft public defensiveFacility ;

    // hero contract
    IMITNft public hero ;

    // stake contract address
    IMITStakingNFT public iMITStaking ;

    // Mit contract
    IERC20 public mitToken ;

    // delay blockNo
    uint256 public delayBlockNo = 10;

    // quanlity rate
    uint256 [] public upgradeRate = [9000, 7500, 5000, 0, 0] ;

    // give rate
    uint256 public giveRate = 50 ;

    // max enable quality
    uint256 public maxEnableQuality = 4 ;

    constructor(address sign, address iMITStakingAddr, address mitAddr, address spaceshipAddr,
        address defensiveFacilityAddr, address heroAddr) BaseManager(sign, "UpgradeManager", "v1.0.0") {
        iMITStaking = IMITStakingNFT(iMITStakingAddr) ;
        mitToken = IERC20(mitAddr) ;
        spaceship = IMITNft(spaceshipAddr) ;
        defensiveFacility = IMITNft(defensiveFacilityAddr) ;
        hero = IMITNft(heroAddr) ;
    }

    ////////////////////////////////////////////////
    //             Events
    ////////////////////////////////////////////////
    event UpgradeEvent(address account ,uint256 mainTokenId, uint256 extraTokenId, KIND kind, uint256 claimBlockNo, uint256 upgradeId) ;
    event ClaimEvent(uint256 upgradeId, bool success, uint256 blockNum, bytes32 hash, uint256 rate, uint16 quality, uint256 random) ;
    ///////////////////////////////////////////
    //          config manager
    ///////////////////////////////////////////

    function setUpgradeFee(uint256 _upgradeFee) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        upgradeFee = _upgradeFee ;
        return true ;
    }

    function initNftAddr(address spaceshipAddr, address defensiveFacilityAddr, address heroAddr) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        spaceship = IMITNft(spaceshipAddr) ;
        defensiveFacility = IMITNft(defensiveFacilityAddr) ;
        hero = IMITNft(heroAddr) ;
        return true ;
    }

    function setMITStaking(address mitStakingAddr) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        iMITStaking = IMITStakingNFT(mitStakingAddr) ;
        return true;
    }

    function setMitToken(address mitTokenAddr) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        mitToken = IERC20(mitTokenAddr) ;
        return true ;
    }

    function setUpgradeRate(uint256 [] memory upRate) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        upgradeRate = upRate ;
        return true ;
    }

    function setMaxEnableQuality(uint256 max) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        maxEnableQuality = max ;
        return true ;
    }

    function setDelayBlockNo(uint256 dBlockNo) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        delayBlockNo = dBlockNo ;
        return true ;
    }

    function setGiveRate(uint256 gRate) external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        giveRate = gRate ;
        return true ;
    }

    function combinedGene(uint16 [] memory traits) public pure returns(uint256) {
        // quality-race-style
        uint256 genes = 0 ;
        for(uint256 i = 0; i < traits.length; i++) {
            genes = genes << 16 ;
            genes = genes | traits[i] ;
        }
        return genes ;
    }

    function decodeGene(uint256 gene) public pure returns (uint16 [] memory) {
        // quality-race-style
        uint16 [] memory rst = new uint16[](3);
        for(uint256 i = 0; i < 3; i++) {
            rst[2 - i] = uint16(gene & uint256(type(uint16).max));
            gene = gene >> 16;
        }
        return rst;
    }

    function upgrade(uint256 mainTokenId, uint256 extraTokenId, KIND kind) external nonReentrant returns(bool) {
        require(mainTokenId != extraTokenId, "You need to provide two NFTs!") ;
        // cost upgradeFee
        if(upgradeFee > 0) {
            bool isOk = mitToken.transferFrom(_msgSender(), address(this), upgradeFee) ;
            require(isOk, "Insufficient NFT upgrade fee!") ;
        }

        // check nft status
        uint256 [] memory genes ;
        address [] memory owners ;

        // transfer NFT
        uint256 [] memory tIds = new uint256[](2);
        tIds[0] = mainTokenId ;
        tIds[1] = extraTokenId ;
        if(kind == KIND.SPACESHIP) {
            (genes,owners) = spaceship.getNftOwnerGensByIds(tIds) ;
            require(owners[0] == _msgSender() && owners[1] == _msgSender(), "You are not the owner of the Spaceship NFT!") ;
            require(genes[0] > 0 && genes[1] > 0, "Your Spaceship NFT gene has not been initialized!") ;

            uint16 [] memory mainTokenDecodeGens = decodeGene(genes[0]) ;
            uint16 [] memory extraTokenDecodeGens = decodeGene(genes[1]) ;
            require(mainTokenDecodeGens[0] == extraTokenDecodeGens[0], "Only Spaceship NFTs of the same quality can be upgraded") ;
            require(mainTokenDecodeGens[0] < maxEnableQuality, "Your Spaceship NFT quality is already top!") ;

            spaceship.safeTransferFrom(_msgSender(), address(this), mainTokenId) ;
            spaceship.safeTransferFrom(_msgSender(), address(iMITStaking), extraTokenId) ;
        } else if(kind == KIND.DEFENSIVEFACILITY) {
            (genes,owners)  = defensiveFacility.getNftOwnerGensByIds(tIds) ;
            require(owners[0] == _msgSender() && owners[1] == _msgSender(), "You are not the owner of the DefensiveFacility NFT!") ;
            require(genes[0] > 0 && genes[1] > 0, "Your DefensiveFacility NFT gene has not been initialized!") ;

            uint16 [] memory mainTokenDecodeGens = decodeGene(genes[0]) ;
            uint16 [] memory extraTokenDecodeGens = decodeGene(genes[1]) ;
            require(mainTokenDecodeGens[0] == extraTokenDecodeGens[0], "Only DefensiveFacility NFTs of the same quality can be upgraded") ;
            require(mainTokenDecodeGens[0] < maxEnableQuality, "Your DefensiveFacility NFT quality is already top!") ;

            defensiveFacility.safeTransferFrom(_msgSender(), address(this), mainTokenId) ;
            defensiveFacility.safeTransferFrom(_msgSender(), address(iMITStaking), extraTokenId) ;
        } else if(kind == KIND.HERO) {
            (genes,owners) = hero.getNftOwnerGensByIds(tIds) ;
            require(owners[0] == _msgSender() && owners[1] == _msgSender(), "You are not the owner of the Hero NFT!") ;
            require(genes[0] > 0 && genes[1] > 0, "Your Hero NFT gene has not been initialized!") ;

            uint16 [] memory mainTokenDecodeGens = decodeGene(genes[0]) ;
            uint16 [] memory extraTokenDecodeGens = decodeGene(genes[1]) ;
            require(mainTokenDecodeGens[0] == extraTokenDecodeGens[0], "Only Hero NFTs of the same quality can be upgraded") ;
            require(mainTokenDecodeGens[0] < maxEnableQuality, "Your Hero NFT quality is already top!") ;

            hero.safeTransferFrom(_msgSender(), address(this), mainTokenId) ;
            hero.safeTransferFrom(_msgSender(), address(iMITStaking), extraTokenId) ;
        } else {
            require(true, "Type not supported for NFT upgrade!") ;
        }

        // store record
        upgradeRecords.push(UpgradeRecord({ account: _msgSender(), kind: kind, mainTokenId: mainTokenId, mainGens: genes[0],
        extraTokenId: extraTokenId, extraGens: genes[1], claimBlockNo: block.number + delayBlockNo, isClaimed:false })) ;

        // event
        emit UpgradeEvent(_msgSender(), mainTokenId, extraTokenId, kind, block.number + delayBlockNo, upgradeRecords.length - 1) ;

        return true ;
    }

    function claim(uint256 upgradeId, uint256 blockNum, bytes32 hash, bytes memory signature) external nonReentrant returns(bool) {
        UpgradeRecord memory upgradeRecord = upgradeRecords[upgradeId] ;
        require(upgradeRecord.claimBlockNo <= block.number && blockNum == upgradeRecord.claimBlockNo, "Your NFT is being upgraded, please try again later!") ;
        require(upgradeRecord.account == _msgSender() && upgradeRecord.isClaimed == false, "Your upgraded NFT has been claimed!") ;
        uint256 blockHash = uint256(hash) ;
        require(blockHash > 0, "Your upgraded NFT has been claimed!") ;
        checkClaimSign(upgradeId, blockNum, hash, signature) ;
        blockHash = blockHash >> 4 ;
        uint256 upgradeRateVal = blockHash % 10000 ;
        uint16 [] memory mainTokenDecodeGens = decodeGene(upgradeRecord.mainGens) ;
        blockHash = blockHash >> 14 ;
        uint256 luckNumber = blockHash ;
        IMITNft nftContractAddr = getContractByKind(upgradeRecord.kind) ;
        uint16 quality = mainTokenDecodeGens[0];
        bool isGive = false ;
        bool isSuccess = false ;
        if(upgradeRateVal < upgradeRate[ mainTokenDecodeGens[0] - 1 ]) {
            // successful
            mainTokenDecodeGens[0] ++ ;
            isSuccess = true ;

            uint256 newGen = combinedGene(mainTokenDecodeGens) ;

            // upgrade gen
            nftContractAddr.setGens(newGen, upgradeRecord.mainTokenId) ;
        } else {
            // fail
            isGive = ((blockHash >> 5) % 100) < giveRate ;
        }

        // lottery extraToken
        iMITStaking.lottery(upgradeRecord.extraTokenId, luckNumber, address(nftContractAddr), upgradeRecord.account, isGive) ;

        // back
        nftContractAddr.transferFrom(address(this), upgradeRecord.account, upgradeRecord.mainTokenId) ;
        upgradeRecords[upgradeId].isClaimed = true ;

        // emit
        emit ClaimEvent(upgradeId, isSuccess, blockNum, hash, upgradeRate[ mainTokenDecodeGens[0] - 1 ], quality, upgradeRateVal) ;

        return true ;
    }

    function checkClaimSign(uint256 upgradeId, uint256 blockNum, bytes32 hash, bytes memory signature) public view {
        // cal hash
        bytes memory encodeData = abi.encode(
            keccak256(abi.encodePacked("claim(uint256 upgradeId,uint256 blockNum,bytes32 hash,address owner)")),
            upgradeId,
            blockNum,
            hash,
            _msgSender()
        ) ;
        (bool success,) = checkSign(encodeData, signature) ;
        require(success, "claim: The operation of claim permission is wrong!") ;
    }

    function getContractByKind(KIND kind) public view returns(IMITNft) {
        if(kind == KIND.SPACESHIP) {
            return spaceship ;
        } else if(kind == KIND.DEFENSIVEFACILITY) {
            return defensiveFacility;
        } else if(kind == KIND.HERO){
            return hero ;
        } else {
            require(false, "No suitable NFT contract matched!") ;
        }
        return spaceship;
    }

    function upgradeRecordsLen() external view returns(uint256 ) {
        return upgradeRecords.length ;
    }

    function pageUpgradeRecords(uint256 page, uint256 limit) external view returns(UpgradeRecord [] memory) {
        uint256 startIndex = page * limit ;
        uint256 len = upgradeRecords.length - startIndex ;

        if(len > limit) {
            len = limit ;
        }

        if(startIndex >= upgradeRecords.length) {
            len = 0 ;
        }

        UpgradeRecord [] memory upgradeRecordArr = new UpgradeRecord[](len) ;
        for(uint256 i = 0; i < len; i++) {
            upgradeRecordArr[i] = UpgradeRecord({account: upgradeRecords[startIndex + i].account,
            kind: upgradeRecords[startIndex + i].kind, mainTokenId: upgradeRecords[startIndex + i].mainTokenId,
            mainGens: upgradeRecords[startIndex + i].mainGens, extraTokenId: upgradeRecords[startIndex + i].extraTokenId,
            extraGens: upgradeRecords[startIndex + i].extraGens, claimBlockNo: upgradeRecords[startIndex + i].claimBlockNo,
            isClaimed: upgradeRecords[startIndex + i].isClaimed}) ;
        }

        return upgradeRecordArr;
    }

    function onERC721Received(address, address from, uint256, bytes calldata) external pure override returns (bytes4) {
        require(from != address(0x0));
        return IERC721Receiver.onERC721Received.selector;
    }
}
