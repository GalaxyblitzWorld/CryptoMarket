// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol" ;
import "@openzeppelin/contracts/security/Pausable.sol" ;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract OfficialLock is AccessControlEnumerable {

    // mapping token => unlock block time
    mapping(address => uint256) public lockTimeMap ;
    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    // add token lock info
    function addLock(address contractAddr, uint256 unlockTime) external onlyRole(DEFAULT_ADMIN_ROLE) returns(bool) {
        require(contractAddr != address(0x0), "OfficialLock addLock : The contract address cannot be zero address!") ;
        require(block.timestamp < unlockTime, "OfficialLock addLock : The token unlock time is invalid!") ;
        if(lockTimeMap[contractAddr] > 0) {
            uint256 preLockTime = lockTimeMap[contractAddr] ;
            require(preLockTime < unlockTime, "OfficialLock addLock : Early unlocking of tokens is not allowed!") ;
        }
        lockTimeMap[contractAddr] = unlockTime ;
        return true ;
    }

    // claim token
    function claim(address contractAddr) external onlyRole(DEFAULT_ADMIN_ROLE) returns(bool) {
        require(lockTimeMap[contractAddr] > 0 && lockTimeMap[contractAddr] < block.timestamp, "OfficialLock claim : The token has not been unlocked yet!") ;
        IERC20 token = IERC20(contractAddr) ;
        uint256 balance = token.balanceOf(address(this)) ;
        if(balance > 0) {
            token.transfer(_msgSender(), balance) ;
        }
        return true ;
    }

    // get current
    function current() external view returns(uint256) {
        return block.timestamp ;
    }
}
