// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMintManager {
    function mintOfficial(uint256 [] memory tokenIds, address owner, uint8 style, uint256 cIndex, uint8 kind) external returns (bool) ;
    function mintSuitOfficial(uint256 [] memory sIds, uint256 [] memory dIds, uint256 [] memory hIds, address owner, uint8 style, uint256 cIndex) external returns (bool) ;
}
