// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";

contract MusebotAi is ERC721URIStorage,ERC721Royalty {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor(address owner) ERC721("MuseToken","MusebotAi") {
        _setDefaultRoyalty(owner, 500);
    }

    function mintOne(string memory tokenURIs)
        public
        returns (uint256)
    {
        _tokenIds.increment();

        uint256 newTokenId = _tokenIds.current();
        _safeMint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURIs);

        return newTokenId;
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721URIStorage,ERC721) returns (string memory) {
        return ERC721URIStorage.tokenURI(tokenId);
    }

    function _burn(uint256 tokenId) internal virtual override(ERC721URIStorage,ERC721Royalty) {
        ERC721URIStorage._burn(tokenId);
        _resetTokenRoyalty(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721,ERC721Royalty) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}