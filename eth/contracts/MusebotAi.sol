// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract MusebotAi is ERC1155 {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // storage for token's uri
    mapping(uint256 => string) private _Uris;

    constructor() ERC1155("") {}

    function mintOne(string memory tokenURIs)
        public
    {
        _tokenIds.increment();

        uint256 newTokenId = _tokenIds.current();
        _mint(msg.sender, newTokenId, 1, "");
        _Uris[newTokenId] = tokenURIs;
    }

    function uri(uint256 id) public view virtual override returns (string memory) {
        return _Uris[id];
    }
}