// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol" ;
import "@openzeppelin/contracts/security/Pausable.sol" ;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol" ;
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol" ;
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "../MITNFT/IMITNft.sol" ;
import "../Common/MyMath.sol";

contract MITStaking is Pausable, ReentrancyGuard, AccessControlEnumerable {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    using MyMath for uint256 ;

    // MIT token contract address
    IERC20 public MITToken ;

    // name
    string public name ;

    // start BlockNumber
    uint256 public start = 0;

    // end BlockNumber
    uint256 public end = 0;

    // reward per block
    uint256 public rewardRate = 0;

    // total mitToken count
    uint256 public total ;

    struct Account {
        // account address
        address account ;

        // nft tokenIds
        uint256 amount ;

        // claim
        uint256 claimed ;

        // total reward
        uint256 reward ;
    }

    // staking Account
    Account [] public accounts ;

    // count account
    mapping(address => uint256) public accountStakeIndex ;

    // last update time
    uint256 public lastUpdateRewardTime ;

    // last total reward token
    uint256 public lastAllRewardToken ;

    // player last all reward token
    mapping(address => uint256) public accountLastAllRewardToken;

    //////////////////////////////////////
    //           events
    //////////////////////////////////////
    event MITStakeEvent(address account, string name, uint256 index, uint256 amount) ;
    event MITUnStakeEvent(address account, string name, uint256 amount) ;
    event MITClaimEvent(address account, string name, uint256 reward, uint256 claimed) ;

    constructor (address mitToken, uint256 totalRwd, uint256 startBn, uint256 endBn, string memory pName) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
        MITToken = IERC20(mitToken) ;
        start = startBn ;
        end = endBn ;
        name = pName ;
        rewardRate = totalRwd / (end - start) ;
    }

    function pause() external virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "must have pauser role to pause");
        _pause();
    }

    function unpause() external virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "must have pauser role to unpause");
        _unpause();
    }

    // stake NFT
    function mitStake(uint256 amount) external updateReward whenNotPaused nonReentrant returns(bool) {
        // check data
        require(amount > 0, "Staking MIT cannot be zero!") ;
        require(end == 0 || end > block.number, "Staking MIT activity has ended!") ;

        // transfer
        bool isOk = MITToken.transferFrom(_msgSender(), address(this), amount) ;
        require(isOk, "MIT Transfer Fail") ;

        // store Record
        total += amount ;
        if(accounts.length < 1 || accounts[accountStakeIndex[_msgSender()]].account != _msgSender()) {
            accountStakeIndex[_msgSender()] = accounts.length ;
            accounts.push(Account({
                account: _msgSender(),
                amount: amount,
                claimed: 0,
                reward: 0
            })) ;
        } else {
            accounts[accountStakeIndex[_msgSender()]].amount += amount ;
        }
        emit MITStakeEvent(_msgSender(), name, accountStakeIndex[_msgSender()], amount) ;
        return true ;
    }

    // update reward
    modifier updateReward() {
        if(block.number > start) {
            uint256 currentRewardTime = (end == 0 || block.number < end) ? block.number : end ;
            lastUpdateRewardTime = lastUpdateRewardTime < start ? start : lastUpdateRewardTime ;
            uint256 timeSpace = currentRewardTime.sub(lastUpdateRewardTime, "Time interval calculation error!") ;
            lastUpdateRewardTime = currentRewardTime ;

            if(total > 0) {
                uint256 lastMintAmount = (timeSpace.mul(rewardRate, "mint token amount calculation error!")
                .mul(1e18, "Accuracy expansion failure!"))
                .div(total, "div total NFT count calculation error!");
                lastAllRewardToken = lastAllRewardToken.add(lastMintAmount, "sum mint token amount calculation error!") ;
                if(accounts[accountStakeIndex[_msgSender()]].account == _msgSender()) {
                    uint256 accountCount = accounts[accountStakeIndex[_msgSender()]].amount ;
                    uint256 accountSrcReward = accounts[accountStakeIndex[_msgSender()]].reward ;
                    uint256 accountMintSub = lastAllRewardToken.sub(accountLastAllRewardToken[_msgSender()], "account mint token amount calculation error!") ;
                    uint256 currentReward = accountCount.mul(accountMintSub, "account current mint token amount calculation error!").div(1e18, "Accuracy expansion failure!") ;
                    accounts[accountStakeIndex[_msgSender()]].reward = currentReward.add(accountSrcReward, "account mint token amount calculation error!") ;
                }
                accountLastAllRewardToken[_msgSender()] = lastAllRewardToken ;
            }
        }
        _;
    }

    // unstake NFT
    function mitUnStake(uint256 amount) external updateReward whenNotPaused nonReentrant returns(bool) {
        require(accounts.length > 0 && accounts[accountStakeIndex[_msgSender()]].account == _msgSender(), "no operating authority!") ;
        uint256 userStakeCount = accounts[accountStakeIndex[_msgSender()]].amount ;
        require(userStakeCount > 0 && userStakeCount >= amount, "Insufficient MIT") ;

        accounts[accountStakeIndex[_msgSender()]].amount = userStakeCount.sub(amount, "claim MIT sub fail") ;
        MITToken.transfer(_msgSender(), amount) ;

        // update total
        total -= amount ;

        // transfer reward
        if(accounts[accountStakeIndex[_msgSender()]].reward > 0) {
            _claim() ;
        }

        emit MITUnStakeEvent(_msgSender(), name, amount) ;
        return true ;
    }

    // claim MIT
    function mitRewardClaim() external updateReward nonReentrant whenNotPaused returns(bool) {
        require(accounts.length > 0 && accounts[accountStakeIndex[_msgSender()]].account == _msgSender(), "no operating authority!") ;
        require(accounts[accountStakeIndex[_msgSender()]].reward > 0, "Insufficient MIT") ;
        _claim() ;
        return true ;
    }

    function _claim() private {
        // transfer reward
        uint256 reward = accounts[accountStakeIndex[_msgSender()]].reward ;
        bool isOk = MITToken.transfer(_msgSender(), reward) ;
        require(isOk, "MIT transfer failed") ;
        accounts[accountStakeIndex[_msgSender()]].claimed += reward;
        accounts[accountStakeIndex[_msgSender()]].reward = 0;
        emit MITClaimEvent(_msgSender(), name, reward, accounts[accountStakeIndex[_msgSender()]].claimed) ;
    }

    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(total == 0, "The accounts has not been unstake") ;
        uint256 balance = MITToken.balanceOf(address (this)) ;
        if(balance > 0) {
            MITToken.transfer(_msgSender(), balance) ;
        }
    }

    function pageAccount(uint256 page, uint256 limit) external view returns(Account [] memory, uint256) {
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
            accountArr[i] = Account({account: accounts[startIndex + i].account, amount: accounts[startIndex + i].amount,
            claimed: accounts[startIndex + i].claimed, reward: accounts[startIndex + i].reward}) ;
        }
        return (accountArr, accounts.length);
    }

    function getAccountInfo(address account) external view returns (Account memory) {
        return accounts[ accountStakeIndex[account] ] ;
    }

    function accountLen() external view returns(uint256) {
        return accounts.length ;
    }

    function getReward(address owner) external view returns(uint256 count, uint256 accountCount, uint256 reward, uint256 claimed, uint256 bn) {
        if(block.number > start && total > 0 && accounts[accountStakeIndex[owner]].account == owner) {
            uint256 currentRewardTime = (end == 0 || block.number < end) ? block.number : end ;
            uint256 lastMintAmount = (currentRewardTime.sub(lastUpdateRewardTime, "").mul(rewardRate, "")
            .mul(1e18, ""))
            .div(total, "");
            uint256 lastAllReward = lastAllRewardToken.add(lastMintAmount, "") ;
            accountCount = accounts[accountStakeIndex[owner]].amount ;
            uint256 accountSrcReward = accounts[accountStakeIndex[owner]].reward ;
            uint256 accountMintSub = lastAllReward.sub(accountLastAllRewardToken[owner], "") ;
            uint256 currentReward = accountCount.mul(accountMintSub, "").div(1e18, "") ;
            reward = currentReward.add(accountSrcReward, "") ;
            claimed = accounts[accountStakeIndex[owner]].claimed ;
        } else if(accounts[accountStakeIndex[owner]].account == owner) {
            accountCount = accounts[accountStakeIndex[owner]].amount ;
        }
        return (total, accountCount, reward, claimed, block.number);
    }
}
