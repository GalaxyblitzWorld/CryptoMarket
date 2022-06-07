// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol" ;
import "@openzeppelin/contracts/security/Pausable.sol" ;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol" ;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol" ;
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol" ;
contract MitGameSwap is AccessControl, Pausable, EIP712 {

    bytes32 public constant SIGN_ROLE = keccak256("SIGN_ROLE");

    // record request id
    mapping(uint256 => bool) public orderNumExists ;

    modifier orderNumRepeat (uint256 rId){
        require(rId > 0, "Incorrect request id") ;
        require(orderNumExists[rId] == false, "repeat request") ;
        _;
        orderNumExists[rId] = true ;
    }

    // token erc20
    IERC20 public token ;

    // sign Addr
    address public signAddr ;

    /////////////////////////////////////////////////
    //                  events
    /////////////////////////////////////////////////
    event MitClaimEvent(address account, uint256 amount, uint256 orderNum) ;

    constructor(address sign, address tokenAddr) EIP712("MitGameSwap", "v1.0.0") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(SIGN_ROLE, sign);
        token = IERC20(tokenAddr) ;
        signAddr = sign ;
    }

    function setSignAccount(address sign) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signAddr = sign ;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause() ;
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause() ;
    }

    // user claim
    function mitClaim(uint256 amount,uint256 orderNum, bytes memory signature) external orderNumRepeat(orderNum) whenNotPaused {
        require(amount > 0, "Incorrect amount of tokens withdrawn") ;
        checkClaimSign(amount, orderNum, signature) ;
        bool isOk = token.transfer(_msgSender(), amount) ;
        require(isOk, "MitToken Transfer fail") ;
        emit MitClaimEvent(_msgSender(), amount, orderNum) ;
    }

    // check claim signature
    function checkClaimSign(uint256 amount,uint256 orderNum, bytes memory signature) private view {
        // cal hash
        bytes memory encodeData = abi.encode(
            keccak256(abi.encodePacked("mitClaim(address owner,uint256 amount,uint256 orderNum)")),
            _msgSender(),
            amount,
            orderNum
        ) ;

        (address recovered, ECDSA.RecoverError error) = ECDSA.tryRecover(_hashTypedDataV4(keccak256(encodeData)), signature);
        require(error == ECDSA.RecoverError.NoError && recovered == signAddr, "Incorrect request signature") ;
    }

    // batchTransfer only test
    function batchTransfer(address [] memory to, uint256 [] memory amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to.length == amount.length, "Parameter error") ;
        for(uint256 i = 0; i < to.length; i++) {
            bool isOk = token.transfer(to[i], amount[i]) ;
            require(isOk, "Mit Transfer Fail") ;
        }
    }

    // widthdraw
    function widthdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 amount = token.balanceOf(address (this)) ;
        if(amount > 0) {
            token.transfer(_msgSender(), amount) ;
        }
    }
}
