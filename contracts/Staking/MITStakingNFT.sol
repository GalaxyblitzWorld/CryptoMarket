// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/security/Pausable.sol" ;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol" ;
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol" ;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol" ;
import "../MITToken/MitToken.sol";
import "../MITNFT/IMITNft.sol" ;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Counters.sol" ;

contract MITStakingNFT is Pausable, ReentrancyGuard, AccessControlEnumerable, IERC721Receiver {

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant INVOKE_ROLE = keccak256("MANAGER_ROLE");

    using Counters for Counters.Counter;
    Counters.Counter private stakeTracker;

    // ERC Contract Address
    IERC20 public erc20Token ;

    // stake share
    uint256 public share ;

    // min share
    uint256 public minShareCount ;

    // max share
    uint256 public maxShareCount;

    // unstake share interval
    uint256 public delayTime;

    // stake record
    struct StakeRecord {
        // account
        address account ;

        // stake time
        uint256 stakeTime ;

        // stakeId
        uint256 sId;
    }

    // store config
    StakeRecord [] public stakeRecords ;

    // mapping (sId => index)
    mapping(uint256 => uint256) public sIDToIndex ;

    // NFT Reward Record
    struct RewardRecord {
        // stake account
        address account ;

        // ERC721 tokenId
        uint256 tokenId ;

        // ERC721 contract Address
        address nftContractAddr ;

        // reward was claim ? (default false)
        bool isClaimed ;
    }

    // store Reward
    RewardRecord [] public rewardRecords ;

    // reward count
    mapping(address => mapping(uint256 => bool)) public tokenIdHasReward ;

    ///////////////////////////////////////////
    //               events
    ///////////////////////////////////////////
    event StakeEvent(address account, uint256 timestamp, uint256 delayTime,uint256 sId, uint256 logId) ;
    event UnStakeEvent(uint256 sId) ;
    event PrizeEvent(uint256 index) ;
    event LotteryEvent(RewardRecord reward, address srcOwner, uint256 index) ;
    ///////////////////////////////////////////
    //               config
    ///////////////////////////////////////////
    constructor(address mitToken, uint256 _share, uint256 _minShareCount, uint256 _maxShareCount, uint256 _delayTime)  {
        erc20Token = IERC20(mitToken) ;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        share = _share ;
        minShareCount = _minShareCount ;
        maxShareCount = _maxShareCount ;
        delayTime = _delayTime ;
    }

    function setDelayTime(uint256 _delayTime) external onlyRole(DEFAULT_ADMIN_ROLE) {
        delayTime = _delayTime ;
    }

    function pause() external virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "MITStaking: must have pauser role to pause");
        _pause();
    }

    function unpause() external virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "MITStaking: must have pauser role to unpause");
        _unpause();
    }

    // stake
    function stake(uint256 count, uint256 logId) external whenNotPaused nonReentrant returns(bool){
        require(count >= minShareCount && count <= maxShareCount, string(abi.encodePacked("Staking tokens share should be in [", Strings.toString(minShareCount),",", Strings.toString(maxShareCount), "]"))) ;
        // start transfer
        bool isOk = erc20Token.transferFrom(_msgSender(), address (this), share * count) ;
        require(isOk, "Staking token transfer failed!") ;

        for(uint256 i = 0 ; i < count; i++) {
            // create stake ID
            stakeTracker.increment();

            // store index Rate
            sIDToIndex[ stakeTracker.current() ] = stakeRecords.length ;

            // addr record
            stakeRecords.push(StakeRecord({ account: _msgSender(), stakeTime: block.timestamp, sId: stakeTracker.current() })) ;

            // emit event
            emit StakeEvent(_msgSender(), block.timestamp, delayTime, stakeTracker.current(), logId) ;
        }
        return true ;
    }

    // unstake descending order
    function unStake(uint256 [] memory sIds) external whenNotPaused nonReentrant returns(bool) {
        for(uint256 i = 0; i < sIds.length; i++) {
            uint256 srcIndex = sIDToIndex[ sIds[i] ] ;
            StakeRecord memory srcStakeRecord = stakeRecords[ srcIndex ] ;
            require(srcStakeRecord.account == _msgSender(), "The stake record does not exist or has been successfully withdraw!") ;
            require(block.timestamp - srcStakeRecord.stakeTime >= delayTime, "Insufficient stake time!") ;

            delete sIDToIndex[ sIds[i] ] ;
            StakeRecord memory dstStakeRecord = stakeRecords[ stakeRecords.length - 1 ] ;
            sIDToIndex[ dstStakeRecord.sId ] = srcIndex ;

            // del stakeRecord
            stakeRecords[ srcIndex ] = dstStakeRecord ;

            // del last
            stakeRecords.pop() ;

            // transfer
            bool isOk = erc20Token.transfer(_msgSender(), share) ;
            require(isOk, "Unstake token transfer failed!") ;

            // event
            emit UnStakeEvent(sIds[i]) ;
        }

        return true ;
    }

    // lottery
    function lottery(uint256 tokenId, uint256 random, address nftAddr, address srcOwner, bool isGive) external whenNotPaused nonReentrant onlyRole(INVOKE_ROLE) returns(bool){
        require(tokenIdHasReward[nftAddr][tokenId] == false, "Prizes have been distributed!") ;
        require(IMITNft(nftAddr).ownerOf(tokenId) == address(this), "Prize NFT does not exist!") ;
        tokenIdHasReward[nftAddr][tokenId] = true ;
        if(isGive && stakeRecords.length > 0) {
            // Determine the winning user
            uint256 index = random % stakeRecords.length ;
            RewardRecord memory reward = RewardRecord({account: stakeRecords[index].account, tokenId: tokenId, nftContractAddr: nftAddr, isClaimed: false }) ;
            rewardRecords.push(reward) ;
            emit LotteryEvent(reward, srcOwner, rewardRecords.length - 1) ;
        } else {
            // nft burn
            uint256 [] memory tid = new uint256[](1) ;
            tid[0] = tokenId ;
            IMITNft(nftAddr).batchBurn(tid) ;
        }

        return true ;
    }

    // prize nft
    function prize(uint256 [] memory rIndexs) external whenNotPaused nonReentrant returns(bool){
        require(rIndexs.length > 0, "The list of prizes to receive cannot be empty") ;
        for(uint256 i = 0; i < rIndexs.length; i++) {
            RewardRecord memory reward = rewardRecords[rIndexs[i]] ;
            require(reward.isClaimed == false, "The prize has been claimed!") ;
            require(reward.account == _msgSender(), "You have no prizes to claim!") ;
            rewardRecords[rIndexs[i]].isClaimed = true;

            // transfer NFT
            IMITNft(reward.nftContractAddr).safeTransferFrom(address(this), _msgSender(), reward.tokenId) ;

            // reset tokenId status
            tokenIdHasReward[reward.nftContractAddr][reward.tokenId] = false ;

            // event
            emit PrizeEvent(rIndexs[i]) ;
        }
        return true ;
    }

    function stakeRecordsLen() external view returns(uint256) {
        return stakeRecords.length ;
    }

    function pageStakeRecords(uint256 page, uint256 limit) external view returns(StakeRecord [] memory) {
        uint256 startIndex = page * limit ;
        uint256 len = stakeRecords.length - startIndex ;

        if(len > limit) {
            len = limit ;
        }

        if(startIndex >= stakeRecords.length) {
            len = 0 ;
        }

        StakeRecord [] memory stakeRecordArr = new StakeRecord[](len) ;

        for(uint256 i = 0; i < len; i++) {
            stakeRecordArr[i] = StakeRecord({account: stakeRecords[startIndex + i].account,
            stakeTime: stakeRecords[startIndex + i].stakeTime, sId: stakeRecords[startIndex + i].sId }) ;
        }

        return stakeRecordArr;
    }

    function rewardRecordsLen() external view returns(uint256) {
        return rewardRecords.length ;
    }

    function pageRewardRecords(uint256 page, uint256 limit) external view returns(RewardRecord [] memory) {
        uint256 startIndex = page * limit ;
        uint256 len = rewardRecords.length - startIndex ;

        if(len > limit) {
            len = limit ;
        }

        if(startIndex >= rewardRecords.length) {
            len = 0 ;
        }

        RewardRecord [] memory rewardRecordsArr = new RewardRecord[](len) ;
        for(uint256 i = 0; i < len; i++) {
            rewardRecordsArr[i] = RewardRecord({account: rewardRecords[startIndex + i].account,
            tokenId: rewardRecords[startIndex + i].tokenId, nftContractAddr: rewardRecords[startIndex + i].nftContractAddr,
            isClaimed: rewardRecords[startIndex + i].isClaimed}) ;
        }
        return rewardRecordsArr;
    }

    function onERC721Received(address, address from, uint256, bytes calldata) external pure override returns (bytes4) {
        require(from != address(0x0));
        return IERC721Receiver.onERC721Received.selector;
    }
}
