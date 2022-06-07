// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol" ;
import "@openzeppelin/contracts/security/Pausable.sol" ;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol" ;
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol" ;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../MITNFT/IMITNft.sol" ;
import "../Common/MyMath.sol";

contract NFTStakingMIT is Pausable, ReentrancyGuard, AccessControlEnumerable, IERC721Receiver {
    bytes32 public constant INVOKE_ROLE = keccak256("INVOKE_ROLE");

    using MyMath for uint256 ;

    // MIT token contract address
    IERC20 public MITToken ;

    struct Config {
        // string name
        string name ;

        // NFT contract Address
        IMITNft nft ;

        // start BlockNumber
        uint256 start ;

        // end BlockNumber
        uint256 end ;

        // reward per block
        uint256 [] rewardRate ;

        // quality condition
        uint16 [] qualityCond ;

        // race condition
        uint16 [] raceCond ;

        // style condition
        uint16 [] styleCond ;

        bool active ;
    }

    // staking pool config list
    Config [] configs ;

    // last update time (cid => (quality => time))
    mapping(uint256 => mapping(uint256 => uint256)) public lastUpdateRewardTime ;

    // last total reward token (cid => (quality => total))
    mapping(uint256 => mapping(uint256 => uint256)) public lastAllRewardToken ;

    // player last all reward token (account => (cId => (quality => total)) )
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public accountLastAllRewardToken;

    // all total nft  (cId => (quality => total))
    mapping(uint256 => mapping(uint256 => uint256)) public nftTotals ;

    // account all total nft  (address => (cId => (quality => total)))
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public accountNftTotals ;

    // ( cId => ( tId => owner ) )
    mapping(uint256 => mapping(uint256 => address)) public nftSrcOwners;

    // (cId => ( tId => quality))
    mapping(uint256 => mapping(uint256 => uint256)) nftQuality ;

    // (address => (cId => (quality => claimed)))
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public accountClaimed ;

    // (address => (cId => (quality => reward)))
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public accountReward ;

    //////////////////////////////////////
    //           events
    //////////////////////////////////////
    event NFTAddConfigEvent(Config config, uint256 cIndex) ;
    event NFTStakeEvent(address account, string name, uint256 cIndex, uint256 tokenId, uint256 quality) ;
    event NFTUnStakeEvent(address account, string name, uint256 cIndex, uint256 tokenId, uint256 quality) ;
    event NFTClaimEvent(address account, string name, uint256 cIndex, uint256 reward, uint256 quality, uint256 claimed) ;

    constructor (address invoker, address mitToken) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(INVOKE_ROLE, invoker) ;
        MITToken = IERC20(mitToken) ;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function onERC721Received(address, address , uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    // add config
    function batchAddConfig(Config [] memory cs) external onlyRole(INVOKE_ROLE) {
        for(uint256 i = 0; i < cs.length; i++) {
            configs.push(cs[i]) ;
            emit NFTAddConfigEvent(cs[i], configs.length - 1) ;
        }
    }

    function delConf(uint256 cId) external onlyRole(INVOKE_ROLE) {
        delete configs[cId] ;
    }

    function decodeGene(uint256 gene) private pure returns (uint16 [] memory) {
        // quality-race-style
        uint16 [] memory rst = new uint16[](3);
        for(uint256 i = 0; i < 3; i++) {
            rst[2 - i] = uint16(gene & uint256(type(uint16).max));
            gene = gene >> 16;
        }
        return rst;
    }

    // stake NFT
    function nftStake(uint256 [] memory tIds, uint256 cIndex, uint256 [] memory qualitys) external updateReward(cIndex, qualitys) whenNotPaused nonReentrant {
        // check data
        require(tIds.length > 0 && tIds.length == qualitys.length, "Parameter error") ;
        Config memory config = configs[cIndex] ;
        require((config.end == 0 || config.end > block.number) && config.active, "Staking ended") ;

        // check nft property
        (uint256 [] memory genes, address [] memory owners) = config.nft.getNftOwnerGensByIds(tIds) ;
        checkNFTGensAndOwner(genes, owners, cIndex, qualitys) ;

        // transfer
        bool isOk = config.nft.safeBatchTransferFrom(_msgSender(), address(this), tIds) ;
        require(isOk, "NFT Transfer fail") ;

        for(uint256 i = 0; i < tIds.length; i++) {
            nftTotals[cIndex][qualitys[i]] += 1;
            accountNftTotals[_msgSender()][cIndex][qualitys[i]] += 1 ;
            nftSrcOwners[cIndex][tIds[i]] = _msgSender() ;
            nftQuality[cIndex][tIds[i]] = qualitys[i] ;
            emit NFTStakeEvent(_msgSender(), config.name, cIndex, tIds[i], qualitys[i]) ;
        }
    }

    // check NFT gens and owner
    function checkNFTGensAndOwner(uint256 [] memory geneArr, address [] memory owners, uint256 cIndex, uint256 [] memory qualitys) private view {
        Config memory config = configs[cIndex] ;
        for(uint256 i = 0; i < geneArr.length; i++) {
            // check
            require(owners[i] == _msgSender(), "not owner") ;
            uint16 [] memory gene = decodeGene(geneArr[i]) ;
            require(geneArr[i] > 0 && qualitys[i] == gene[0], "quality mismatching") ;
            require(checkProp(config.qualityCond, gene[0]), "quality fail") ;
            require(checkProp(config.raceCond, gene[1]), "race fail") ;
            require(checkProp(config.styleCond, gene[2]), "style fail") ;
        }
    }

    // check prop ok
    function checkProp(uint16 [] memory prop, uint16 val) private pure returns (bool) {
        for(uint256 i = 0; i < prop.length; i++) {
            if(prop[i] == val) {
                return true ;
            }
        }
        return prop.length < 1 ;
    }

    // update reward
    modifier updateReward(uint256 cId, uint256 [] memory qualitys) {
        Config memory config = configs[cId] ;
        if(block.number > config.start) {
            uint256 currentRewardTime = (config.end == 0 || block.number < config.end) ? block.number : config.end ;
            for(uint256 i = 0; i < qualitys.length; i++) {
                uint256 lastUpdateRewardTimestamp = lastUpdateRewardTime[cId][qualitys[i]] < config.start ? config.start : lastUpdateRewardTime[cId][qualitys[i]];
                uint256 timeSpace = currentRewardTime.sub(lastUpdateRewardTimestamp, "Time error") ;
                (uint256 lastAllReward, uint256 currentReward) = _calUpdateReward(config.rewardRate[qualitys[i] - 1], cId, qualitys[i], timeSpace, _msgSender()) ;

                lastAllRewardToken[cId][qualitys[i]] = lastAllReward;
                accountLastAllRewardToken[_msgSender()][cId][qualitys[i]] = lastAllReward ;
                accountReward[_msgSender()][cId][qualitys[i]] = currentReward.add(accountReward[_msgSender()][cId][qualitys[i]], "Mint amount error") ;
                lastUpdateRewardTime[cId][qualitys[i]] = currentRewardTime ;
            }
        }
        _;
    }

    // Calculate single reward data
    function _calUpdateReward(uint256 rewardRate, uint256 cId,
        uint256 quality, uint256 timeSpace,address owner) public view returns(uint256 lastAllReward, uint256 currentReward) {
        uint256 accountNftCount = accountNftTotals[owner][cId][quality] ;
        if(nftTotals[cId][quality] < 1) {
            return (0, 0);
        }
        uint256 lastMintAmount = (timeSpace.mul(rewardRate, "Amount error")
        .mul(1e18, "Accuracy failure"))
        .div(nftTotals[cId][quality], "Total error");
        lastAllReward = lastAllRewardToken[cId][quality].add(lastMintAmount, "Mint Amount error") ;
        uint256 accountMintSub = lastAllReward.sub(accountLastAllRewardToken[owner][cId][quality], "Account mint amount error") ;
        currentReward = accountNftCount.mul(accountMintSub, "Account current mint amount error").div(1e18, "Accuracy failure") ;
        return (lastAllReward, currentReward);
    }

    // unstake NFT
    function nftUnStake(uint256 cIndex, uint256 [] memory qualitys, uint256 [] memory tIds) external updateReward(cIndex, qualitys) whenNotPaused nonReentrant {
        require(tIds.length > 0 && tIds.length == qualitys.length, "parameter error") ;
        for(uint256 i = 0; i < tIds.length; i++) {
            // transfer
            require(qualitys[i] == nftQuality[cIndex][tIds[i]], "quality mismatching") ;
            require(_msgSender() == nftSrcOwners[cIndex][tIds[i]], "authority fail") ;
            configs[cIndex].nft.safeTransferFrom(address(this), _msgSender(), tIds[i]) ;
            nftTotals[cIndex][qualitys[i]] -- ;
            accountNftTotals[_msgSender()][cIndex][qualitys[i]] -- ;
            delete nftSrcOwners[cIndex][tIds[i]] ;
            delete nftQuality[cIndex][tIds[i]] ;
            emit NFTUnStakeEvent(_msgSender(), configs[cIndex].name, cIndex, tIds[i], qualitys[i]) ;
        }

        // transfer reward
        _claim(cIndex, qualitys) ;
    }

    // claim MIT
    function nftRewardClaim(uint256 cIndex, uint256 [] memory qualitys) external updateReward(cIndex, qualitys) nonReentrant whenNotPaused {
        _claim(cIndex, qualitys) ;
    }

    function _claim(uint256 cIndex, uint256 [] memory qualitys) private {
        // transfer reward
        for(uint256 i = 0; i < qualitys.length; i++) {
            uint256 reward = accountReward[_msgSender()][cIndex][qualitys[i]] ;
            if(reward > 0) {
                accountReward[_msgSender()][cIndex][qualitys[i]] = 0 ;
                bool isOk = MITToken.transfer(_msgSender(), reward) ;
                require(isOk, "MIT transfer failed") ;
                accountClaimed[_msgSender()][cIndex][qualitys[i]] += reward;
                emit NFTClaimEvent(_msgSender(), configs[cIndex].name, cIndex, reward, qualitys[i], accountClaimed[_msgSender()][cIndex][qualitys[i]]) ;
            }
        }
    }

    function withdraw(uint256 cId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Config memory config = configs[cId] ;
        require(config.active, "already finished") ;
        uint256 totalQualityRewardRate = 0 ;
        uint256 totalMintReward = 0 ;
        for(uint256 i = 0 ; i < config.rewardRate.length; i++) {
            require(nftTotals[cId][i + 1] == 0, "exist unstake") ;
            totalQualityRewardRate += config.rewardRate[i] ;
            totalMintReward += lastAllRewardToken[cId][i + 1] ;
        }
        uint256 blockNum = (config.end > config.start) ? (config.end - config.start) : 0;
        uint256 totalReward = totalQualityRewardRate * blockNum ;
        uint256 balance = totalReward - totalMintReward.div(1e18, "Accuracy failure");
        if(balance > 0) {
            MITToken.transfer(_msgSender(), balance) ;
            configs[cId].active = false;
        }
    }

    function configLen() external view returns(uint256) {
        return configs.length ;
    }

    function getConfig(uint256 cId) external view returns(Config memory) {
       return Config({ nft: configs[cId].nft, name: configs[cId].name,
        start: configs[cId].start, end: configs[cId].end,
        rewardRate: configs[cId].rewardRate, qualityCond: configs[cId].qualityCond,
        raceCond: configs[cId].raceCond, styleCond: configs[cId].styleCond, active: configs[cId].active}) ;
    }

    function getReward(uint256 cId, uint256 [] memory qualitys, address owner) external view
    returns(uint256[] memory totalNft, uint256 [] memory myTotalNft, uint256 [] memory reward, uint256 [] memory claimed, uint256 bn) {
        Config memory config = configs[cId] ;
        totalNft = new uint256[](qualitys.length) ;
        myTotalNft = new uint256[](qualitys.length) ;
        reward = new uint256[](qualitys.length) ;
        claimed = new uint256[](qualitys.length) ;
        if(block.number > config.start) {
            uint256 currentRewardTime = (config.end == 0 || block.number < config.end) ? block.number : config.end ;
            for(uint256 i = 0; i < qualitys.length; i++) {
                uint256 lastUpdateRewardTimestamp = lastUpdateRewardTime[cId][qualitys[i]] < config.start ? config.start : lastUpdateRewardTime[cId][qualitys[i]];
                uint256 timeSpace = currentRewardTime.sub(lastUpdateRewardTimestamp, "Time error") ;
                (, reward[i]) = _calUpdateReward(config.rewardRate[qualitys[i] - 1], cId, qualitys[i], timeSpace, owner) ;
                totalNft[i] = nftTotals[cId][qualitys[i]] ;
                myTotalNft[i] = accountNftTotals[owner][cId][qualitys[i]] ;
                claimed[i] = accountClaimed[owner][cId][qualitys[i]] ;
            }
        } else {
            for(uint256 i = 0; i < qualitys.length; i++) {
                totalNft[i] = nftTotals[cId][qualitys[i]] ;
                myTotalNft[i] = accountNftTotals[owner][cId][qualitys[i]] ;
                claimed[i] = accountClaimed[owner][cId][qualitys[i]] ;
            }
        }
        return (totalNft, myTotalNft, reward, claimed, block.number);
    }
}
