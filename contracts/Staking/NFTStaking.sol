// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol" ;
import "@openzeppelin/contracts/security/Pausable.sol" ;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol" ;
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol" ;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../MITNFT/IMITNft.sol" ;
import "../Common/MyMath.sol";

contract NFTStaking is Pausable, ReentrancyGuard, AccessControlEnumerable, IERC721Receiver{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant INVOKE_ROLE = keccak256("INVOKE_ROLE");

    using MyMath for uint256 ;

    // MIT token contract address
    IERC20 MITToken ;

    struct Config {
        // NFT contract Address
        IMITNft nft ;

        // start BlockNumber
        uint256 start ;

        // end BlockNumber
        uint256 end ;

        // max use stake count
        uint256 maxUseStakeCount;

        // reward per block
        uint256 rewardRate ;

        // total nft count
        uint256 total ;

        // quality condition
        uint16 [] qualityCond ;

        // race condition
        uint16 [] raceCond ;

        // style condition
        uint16 [] styleCond ;

        // status
        bool active ;
    }

    // staking pool config list
    Config [] public configs ;

    struct Account {
        // account address
        address account ;

        // nft tokenIds
        uint256 [] tIds ;

        // claim
        uint256 claimed ;

        // total reward
        uint256 reward ;
    }

    // staking Account
    Account [] public accounts ;

    // count account
    mapping(address => mapping(uint256 => uint256)) public accountStakeIndex ;

    // last update time
    mapping(uint256 => uint256) public lastUpdateRewardTime ;

    // last total reward token
    mapping(uint256 => uint256) public lastAllRewardToken ;

    // player last all reward token
    mapping(address => mapping(uint256 => uint256)) public accountLastAllRewardToken;

    // name mapping
    mapping(uint256 => string) public configNames ;

    //////////////////////////////////////
    //           events
    //////////////////////////////////////
    event NFTAddConfigEvent(Config config, uint256 cIndex) ;
    event NFTDelConfigEvent(Config config) ;
    event NFTUpdateConfigEvent(uint256 [] cIndex, bool active) ;
    event NFTStakeEvent(address account, string name, uint256 cIndex, uint256 index, uint256 [] tokenId) ;
    event NFTUnStakeEvent(address account, string name, uint256 cIndex, uint256 tokenId) ;
    event NFTClaimEvent(address account, string name, uint256 cIndex, uint256 reward, uint256 claimed) ;

    constructor (address invoker, address mitToken) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(INVOKE_ROLE, invoker) ;
        MITToken = IERC20(mitToken) ;
    }

    function pause() external virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "must have pauser role to pause");
        _pause();
    }

    function unpause() external virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "must have pauser role to unpause");
        _unpause();
    }

    function onERC721Received(address, address from, uint256, bytes calldata) external pure override returns (bytes4) {
        require(from != address(0x0));
        return IERC721Receiver.onERC721Received.selector;
    }

    // add config
    function batchAddConfig(Config [] memory cs, string [] memory names) external onlyRole(INVOKE_ROLE) returns (bool) {
        require(cs.length == names.length, "Parameter error") ;
        for(uint256 i = 0; i < cs.length; i++) {
            lastUpdateRewardTime[configs.length] = cs[i].start ;
            configNames[configs.length] = names[i] ;
            configs.push(cs[i]) ;
            emit NFTAddConfigEvent(cs[i], configs.length - 1) ;
        }
        return true ;
    }

    // chanage config status
    function batchUpdateStatus(uint256 [] memory cIds, bool active) external onlyRole(INVOKE_ROLE) returns (bool) {
        for(uint256 i = 0 ; i < cIds.length; i++) {
            configs[cIds[i]].active = active ;
        }
        emit NFTUpdateConfigEvent(cIds, active) ;
        return true ;
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

    // stake NFT
    function nftStake(uint256 [] memory tIds, uint256 cIndex) external updateReward(cIndex) whenNotPaused nonReentrant returns(bool) {
        // check data
        require(tIds.length > 0, "NFT cannot be empty") ;
        Config memory config = configs[cIndex] ;

        uint256 accountPlayerCount = 0 ;
        if(config.maxUseStakeCount > 0) {
            bool stakeEnable = true ;
            if(accounts.length > 0) {
                if(accounts[ accountStakeIndex[_msgSender()][cIndex] ].account == _msgSender()) {
                    stakeEnable = (tIds.length + accounts[ accountStakeIndex[_msgSender()][cIndex] ].tIds.length) <= config.maxUseStakeCount ;
                    accountPlayerCount = accounts[ accountStakeIndex[_msgSender()][cIndex] ].tIds.length ;
                } else {
                    stakeEnable = tIds.length <= config.maxUseStakeCount ;
                }
            } else {
                stakeEnable = tIds.length <= config.maxUseStakeCount ;
            }
            require(stakeEnable, "Exceeds maximum pledge amount") ;
        }

        require(config.active, "Staking suspended") ;
        require(config.end == 0 || config.end > block.number, "Staking ended") ;
        (uint256 [] memory genes, address [] memory owners) = config.nft.getNftOwnerGensByIds(tIds) ;
        checkNFTGensAndOwner(genes, owners, cIndex) ;

        // transfer
        bool isOk = config.nft.safeBatchTransferFrom(_msgSender(), address(this), tIds) ;
        require(isOk, "NFT Transfer Fail") ;

        // store Record
        configs[cIndex].total += tIds.length ;
        if(accountPlayerCount < 1) {
            accountStakeIndex[_msgSender()][cIndex] = accounts.length ;
            accounts.push(Account({
                account: _msgSender(),
                tIds: tIds,
                claimed: 0,
                reward: 0
            })) ;
        } else {
            for(uint256 i = 0; i < tIds.length; i++) {
                accounts[ accountStakeIndex[_msgSender()][cIndex] ].tIds.push(tIds[i]) ;
            }
        }
        emit NFTStakeEvent(_msgSender(), configNames[cIndex], cIndex, accountStakeIndex[_msgSender()][cIndex], tIds) ;
        return true ;
    }

    // check NFT gens and owner
    function checkNFTGensAndOwner(uint256 [] memory genes, address [] memory owners, uint256 cIndex) private view {
        Config memory config = configs[cIndex] ;
        for(uint256 i = 0; i < genes.length; i++) {
            // check
            require(owners[i] == _msgSender(), "Not NFT owner") ;
            uint16 [] memory gens = decodeGene(genes[i]) ;
            require(checkProp(config.qualityCond, gens[0]), "NFT quality does not meet staking conditions") ;
            require(checkProp(config.raceCond, gens[1]), "NFT race does not meet staking conditions") ;
            require(checkProp(config.styleCond, gens[2]), "NFT style does not meet staking conditions") ;
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
    modifier updateReward(uint256 cId) {
        Config memory config = configs[cId] ;
        if(config.active && block.number > config.start) {
            lastUpdateRewardTime[cId] = lastUpdateRewardTime[cId] < config.start ? config.start : lastUpdateRewardTime[cId] ;
            uint256 currentRewardTime = (config.end == 0 || block.number < config.end) ? block.number : config.end ;
            uint256 timeSpace = currentRewardTime.sub(lastUpdateRewardTime[cId], "Time error") ;
            lastUpdateRewardTime[cId] = currentRewardTime ;

            if(config.total > 0) {
                uint256 lastMintAmount = (timeSpace.mul(config.rewardRate, "Amount error")
                .mul(1e18, "Accuracy failure"))
                .div(config.total, "Total error");
                lastAllRewardToken[cId] = lastAllRewardToken[cId].add(lastMintAmount, "Mint Amount error") ;
                if(accounts[accountStakeIndex[_msgSender()][cId]].account == _msgSender()) {
                    uint256 accountNftCount = accounts[accountStakeIndex[_msgSender()][cId]].tIds.length ;
                    uint256 accountSrcReward = accounts[accountStakeIndex[_msgSender()][cId]].reward ;
                    uint256 accountMintSub = lastAllRewardToken[cId].sub(accountLastAllRewardToken[_msgSender()][cId], "Account mint amount error") ;
                    uint256 currentReward = accountNftCount.mul(accountMintSub, "Account current mint amount error").div(1e18, "Accuracy failure") ;
                    accounts[accountStakeIndex[_msgSender()][cId]].reward = currentReward.add(accountSrcReward, "Mint amount error") ;
                }
                accountLastAllRewardToken[_msgSender()][cId] = lastAllRewardToken[cId] ;
            }
        }
        _;
    }

    // unstake NFT
    function nftUnStake(uint256 cIndex, uint256 limit) external updateReward(cIndex) whenNotPaused nonReentrant returns(bool) {
        require(accounts.length > 0 && accounts[accountStakeIndex[_msgSender()][cIndex]].account == _msgSender(), "Authority Fail") ;
        uint256 userStakeCount = accounts[accountStakeIndex[_msgSender()][cIndex]].tIds.length ;
        require(userStakeCount > 0, "Not staking NFT") ;

        // transfer
        uint256 maxCount = limit > userStakeCount ? userStakeCount : limit ;

        for(uint256 i = 0; i < maxCount; i++) {
            // transfer
            uint256 [] memory tIds = accounts[accountStakeIndex[_msgSender()][cIndex]].tIds ;
            configs[cIndex].nft.safeTransferFrom(address(this), _msgSender(), tIds[tIds.length - 1]) ;
            emit NFTUnStakeEvent(_msgSender(), configNames[cIndex], cIndex, tIds[tIds.length - 1]) ;
            accounts[accountStakeIndex[_msgSender()][cIndex]].tIds.pop() ;
        }

        // update config total
        configs[cIndex].total -= maxCount ;

        // transfer reward
        _claim(cIndex) ;
        return true ;
    }

    // claim MIT
    function nftRewardClaim(uint256 cIndex) external updateReward(cIndex) nonReentrant whenNotPaused returns(bool) {
        require(accounts[accountStakeIndex[_msgSender()][cIndex]].account == _msgSender()
            && accounts[accountStakeIndex[_msgSender()][cIndex]].tIds.length > 0, "Authority Fail") ;
        require(accounts[accountStakeIndex[_msgSender()][cIndex]].reward > 0, "No tokens to Claim") ;
        _claim(cIndex) ;
        return true ;
    }

    function _claim(uint256 cIndex) private {
        // transfer reward
        if(accounts[accountStakeIndex[_msgSender()][cIndex]].reward > 0) {
            uint256 reward = accounts[accountStakeIndex[_msgSender()][cIndex]].reward ;
            bool isOk = MITToken.transfer(_msgSender(), reward) ;
            require(isOk, "MIT transfer failed") ;
            accounts[accountStakeIndex[_msgSender()][cIndex]].claimed += reward;
            accounts[accountStakeIndex[_msgSender()][cIndex]].reward = 0;
            emit NFTClaimEvent(_msgSender(), configNames[cIndex], cIndex, reward, accounts[accountStakeIndex[_msgSender()][cIndex]].claimed) ;
        }
    }

    function configLen() external view returns(uint256) {
        return configs.length ;
    }

    function accountsLen() external view returns(uint256) {
        return accounts.length ;
    }

    function pageConfig(uint256 page, uint256 limit) external view returns(Config [] memory, string [] memory) {
        uint256 startIndex = page * limit ;
        uint256 len = configs.length - startIndex ;

        if(len > limit) {
            len = limit ;
        }

        if(startIndex >= configs.length) {
            len = 0 ;
        }

        Config [] memory configArr = new Config[](len) ;
        string [] memory names = new string[](len) ;
        for(uint256 i = 0; i < len; i++) {
            configArr[i] = Config({ nft: configs[startIndex + i].nft,
            start: configs[startIndex + i].start, end: configs[startIndex + i].end, maxUseStakeCount: configs[startIndex + i].maxUseStakeCount,
            rewardRate: configs[startIndex + i].rewardRate, total: configs[startIndex + i].total, qualityCond: configs[startIndex + i].qualityCond,
            raceCond: configs[startIndex + i].raceCond, styleCond: configs[startIndex + i].styleCond, active: configs[startIndex + i].active}) ;
            names[i] = configNames[startIndex + i] ;
        }
        return (configArr, names);
    }

    function pageAccount(uint256 page, uint256 limit) external view returns(Account [] memory ) {
        uint256 startIndex = page * limit ;
        uint256 len = accounts.length - startIndex ;

        if(len > limit) {
            len = limit ;
        }

        if(startIndex >= accounts.length) {
            len = 0 ;
        }

        Account [] memory accountArr = new Account[](len) ;
        for(uint256 i = 0; i < len; i++) {
            accountArr[i] = Account({account: accounts[startIndex + i].account, tIds: accounts[startIndex + i].tIds,
            claimed: accounts[startIndex + i].claimed, reward: accounts[startIndex + i].reward}) ;
        }
        return accountArr;
    }

    function getAccountInfo(address account, uint256 cId) external view returns (Account memory) {
        return accounts[ accountStakeIndex[account][cId] ] ;
    }

    function getReward(address owner, uint256 cId) external view returns (uint256 count, uint256 accountNftCount, uint256 reward, uint256 claimed, uint256 bn) {
        Config memory config = configs[cId] ;
        if(config.active && block.number > config.start && config.total > 0 &&
            accounts[accountStakeIndex[owner][cId]].account == owner) {
            uint256 currentRewardTime = (config.end == 0 || block.number < config.end) ? block.number : config.end ;
            uint256 timeSpace = currentRewardTime.sub(lastUpdateRewardTime[cId], "") ;
            uint256 lastMintAmount = (timeSpace.mul(config.rewardRate, "")
            .mul(1e18, ""))
            .div(config.total, "");
            uint256 lastAllReward = lastAllRewardToken[cId].add(lastMintAmount, "") ;
            accountNftCount = accounts[accountStakeIndex[owner][cId]].tIds.length ;
            reward = calReward(owner, cId, lastAllReward) ;
        }
        return (configs[cId].total, accountNftCount, reward, accounts[accountStakeIndex[owner][cId]].claimed, block.number ) ;
    }

    function calReward(address owner, uint256 cId, uint256 lastAllReward) internal view returns(uint256) {
        uint256 accountSrcReward = accounts[accountStakeIndex[owner][cId]].reward ;
        uint256 accountMintSub = lastAllReward.sub(accountLastAllRewardToken[owner][cId], "") ;
        uint256 currentReward = accounts[accountStakeIndex[owner][cId]].tIds.length.
        mul(accountMintSub, "").
        div(1e18, "") ;
        return currentReward.add(accountSrcReward, "") ;
    }
}
