// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PackripprNFT
 * @notice Standard NFT contract for game assets with royalty support
 */
contract PackripprNFT is ERC721URIStorage, ERC2981, Ownable {
    uint256 private _nextTokenId;

    constructor(
        string memory name,
        string memory symbol,
        address royaltyReceiver,
        uint96 royaltyFeeNumerator // 500 = 5%
    ) ERC721(name, symbol) Ownable(msg.sender) {
        // Set a default royalty for all tokens in this collection
        _setDefaultRoyalty(royaltyReceiver, royaltyFeeNumerator);
    }

    /**
     * @notice Mints a new game asset
     * @param to The address that will own the minted NFT
     * @param uri The metadata URI (IPFS link to JSON)
     */
    function safeMint(
        address to,
        string memory uri
    ) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        return tokenId;
    }

    /**
     * @dev Necessary overrides to support both URIStorage and Royalties
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721URIStorage, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    // Optional: Allow the owner to update default royalties later
    function setDefaultRoyalty(
        address receiver,
        uint96 feeNumerator
    ) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }
}
