// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMITStakingNFT {

    function lottery (uint256 tokenId, uint256 random, address nftAddr, address srcOwner, bool isGive) external returns(bool) ;

}
