// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
import './MusebotAi.sol';

contract MuseMint {
    address public owner;

    constructor(address owneraddr) {
        owner = owneraddr;
    }

    function mintOne(string memory name, string memory tokenURI)
        external
        returns (uint256) {
            MusebotAi museBot = new MusebotAi(owner,name);
            return museBot.mintOne(msg.sender, tokenURI);
        }
} 