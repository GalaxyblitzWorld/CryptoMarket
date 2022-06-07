// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library GenesMath {
    function combinedGene(uint16 [] memory traits) internal pure returns(uint256) {
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

}
