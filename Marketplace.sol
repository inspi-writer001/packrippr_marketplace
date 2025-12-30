// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title GameNFTShop
 * @notice Simple NFT marketplace where ONLY the game owner can list NFTs for sale
 * @dev Players can buy NFTs listed by the owner, payment goes to treasury
 */
contract PackRippr is Ownable, ReentrancyGuard, Pausable {
    
    // ============ State Variables ============
    
    /// @notice Treasury address where all payments go
    address public treasury;
    
    /// @notice Counter for listing IDs
    uint256 private _listingIdCounter;
    
    /// @notice Mapping from listing ID to Listing details
    mapping(uint256 => Listing) public listings;
    
    /// @notice Mapping to check if an NFT is currently listed
    mapping(address => mapping(uint256 => bool)) public isListed;
    
    // ============ Structs ============
    
    struct Listing {
        uint256 listingId;
        address nftContract;
        uint256 tokenId;
        address paymentToken;  // address(0) for ETH/native token
        uint256 price;
        address seller;
        bool isActive;
    }
    
    // ============ Events ============
    
    event NFTListed(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address paymentToken,
        uint256 price
    );
    
    event NFTPurchased(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price
    );
    
    event NFTDelisted(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId
    );
    
    event PriceUpdated(
        uint256 indexed listingId,
        uint256 oldPrice,
        uint256 newPrice
    );
    
    event TreasuryUpdated(
        address indexed oldTreasury,
        address indexed newTreasury
    );
    
    // ============ Constructor ============
    
    constructor(address _treasury, address _initialOwner) Ownable(_initialOwner) {
        require(_treasury != address(0), "Invalid treasury address");
        require(_initialOwner != address(0), "Invalid owner address");
        treasury = _treasury;
    }
    
    // ============ Owner Functions ============
    
    /**
     * @notice List an NFT for sale (Only owner can list)
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param paymentToken Token to accept as payment (address(0) for native token)
     * @param price Price in payment token units
     */
    function listNFT(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price
    ) external onlyOwner whenNotPaused returns (uint256) {
        require(nftContract != address(0), "Invalid NFT contract");
        require(price > 0, "Price must be greater than 0");
        require(!isListed[nftContract][tokenId], "NFT already listed");
        
        // Verify the shop owns this NFT
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == address(this), "Shop doesn't own this NFT");
        
        uint256 listingId = _listingIdCounter++;
        
        listings[listingId] = Listing({
            listingId: listingId,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentToken: paymentToken,
            price: price,
            seller: msg.sender,
            isActive: true
        });
        
        isListed[nftContract][tokenId] = true;
        
        emit NFTListed(listingId, nftContract, tokenId, paymentToken, price);
        
        return listingId;
    }
    
    /**
     * @notice List multiple NFTs at once
     * @param nftContracts Array of NFT contract addresses
     * @param tokenIds Array of token IDs
     * @param paymentTokens Array of payment tokens
     * @param prices Array of prices
     */
    function batchListNFTs(
        address[] calldata nftContracts,
        uint256[] calldata tokenIds,
        address[] calldata paymentTokens,
        uint256[] calldata prices
    ) external onlyOwner whenNotPaused returns (uint256[] memory) {
        require(
            nftContracts.length == tokenIds.length &&
            tokenIds.length == paymentTokens.length &&
            paymentTokens.length == prices.length,
            "Array lengths mismatch"
        );
        
        uint256[] memory listingIds = new uint256[](nftContracts.length);
        
        for (uint256 i = 0; i < nftContracts.length; i++) {
            listingIds[i] = this.listNFT(
                nftContracts[i],
                tokenIds[i],
                paymentTokens[i],
                prices[i]
            );
        }
        
        return listingIds;
    }
    
    /**
     * @notice Remove an NFT from sale
     * @param listingId ID of the listing to remove
     */
    function delistNFT(uint256 listingId) external onlyOwner {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        
        listing.isActive = false;
        isListed[listing.nftContract][listing.tokenId] = false;
        
        emit NFTDelisted(listingId, listing.nftContract, listing.tokenId);
    }
    
    /**
     * @notice Update price of a listed NFT
     * @param listingId ID of the listing
     * @param newPrice New price
     */
    function updatePrice(uint256 listingId, uint256 newPrice) external onlyOwner {
        require(newPrice > 0, "Price must be greater than 0");
        
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        
        uint256 oldPrice = listing.price;
        listing.price = newPrice;
        
        emit PriceUpdated(listingId, oldPrice, newPrice);
    }
    
    /**
     * @notice Update treasury address
     * @param newTreasury New treasury address
     */
    function updateTreasury(address newTreasury) external onlyOwner {
        require(newTreasury != address(0), "Invalid treasury address");
        
        address oldTreasury = treasury;
        treasury = newTreasury;
        
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
    
    /**
     * @notice Withdraw NFT from shop (if not listed or after delisting)
     * @param nftContract NFT contract address
     * @param tokenId Token ID to withdraw
     * @param to Address to send NFT to
     */
    function withdrawNFT(
        address nftContract,
        uint256 tokenId,
        address to
    ) external onlyOwner {
        require(!isListed[nftContract][tokenId], "NFT is currently listed");
        
        IERC721(nftContract).safeTransferFrom(address(this), to, tokenId);
    }
    
    /**
     * @notice Emergency withdraw ERC20 tokens
     * @param token Token address
     * @param amount Amount to withdraw
     */
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
    
    /**
     * @notice Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // ============ Public Purchase Functions ============
    
    /**
     * @notice Buy an NFT from the shop
     * @param listingId ID of the listing to purchase
     */
    function buyNFT(uint256 listingId) external payable nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        
        require(listing.isActive, "Listing not active");
        
        // Handle payment
        if (listing.paymentToken == address(0)) {
            // Native token payment (ETH/MATIC/etc)
            require(msg.value == listing.price, "Incorrect payment amount");
            
            // Send payment to treasury
            (bool success, ) = treasury.call{value: msg.value}("");
            require(success, "Payment transfer failed");
        } else {
            // ERC20 token payment
            require(msg.value == 0, "ETH not accepted for this listing");
            
            IERC20 paymentToken = IERC20(listing.paymentToken);
            require(
                paymentToken.transferFrom(msg.sender, treasury, listing.price),
                "Payment transfer failed"
            );
        }
        
        // Mark as inactive and remove from listed mapping
        listing.isActive = false;
        isListed[listing.nftContract][listing.tokenId] = false;
        
        // Transfer NFT to buyer
        IERC721(listing.nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            listing.tokenId
        );
        
        emit NFTPurchased(
            listingId,
            msg.sender,
            listing.nftContract,
            listing.tokenId,
            listing.price
        );
    }
    
    /**
     * @notice Buy multiple NFTs in one transaction
     * @param listingIds Array of listing IDs to purchase
     */
    function batchBuyNFTs(uint256[] calldata listingIds) external payable nonReentrant whenNotPaused {
        uint256 totalNativePayment = 0;
        
        // First pass: validate and calculate total native payment needed
        for (uint256 i = 0; i < listingIds.length; i++) {
            Listing storage listing = listings[listingIds[i]];
            require(listing.isActive, "Listing not active");
            
            if (listing.paymentToken == address(0)) {
                totalNativePayment += listing.price;
            }
        }
        
        require(msg.value == totalNativePayment, "Incorrect total payment");
        
        // Second pass: process purchases
        for (uint256 i = 0; i < listingIds.length; i++) {
            Listing storage listing = listings[listingIds[i]];
            
            // Handle payment
            if (listing.paymentToken == address(0)) {
                // Native payment already validated, will be sent at end
            } else {
                // ERC20 payment
                IERC20 paymentToken = IERC20(listing.paymentToken);
                require(
                    paymentToken.transferFrom(msg.sender, treasury, listing.price),
                    "Payment transfer failed"
                );
            }
            
            // Mark as inactive
            listing.isActive = false;
            isListed[listing.nftContract][listing.tokenId] = false;
            
            // Transfer NFT
            IERC721(listing.nftContract).safeTransferFrom(
                address(this),
                msg.sender,
                listing.tokenId
            );
            
            emit NFTPurchased(
                listingIds[i],
                msg.sender,
                listing.nftContract,
                listing.tokenId,
                listing.price
            );
        }
        
        // Send total native payment to treasury
        if (totalNativePayment > 0) {
            (bool success, ) = treasury.call{value: totalNativePayment}("");
            require(success, "Payment transfer failed");
        }
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get full details of a listing
     * @param listingId ID of the listing
     */
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
    
    /**
     * @notice Get multiple listings at once
     * @param listingIds Array of listing IDs
     */
    function getListings(uint256[] calldata listingIds) external view returns (Listing[] memory) {
        Listing[] memory result = new Listing[](listingIds.length);
        
        for (uint256 i = 0; i < listingIds.length; i++) {
            result[i] = listings[listingIds[i]];
        }
        
        return result;
    }
    
    /**
     * @notice Check if a specific NFT is listed
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     */
    function isNFTListed(address nftContract, uint256 tokenId) external view returns (bool) {
        return isListed[nftContract][tokenId];
    }
    
    /**
     * @notice Get current listing counter
     */
    function getListingCounter() external view returns (uint256) {
        return _listingIdCounter;
    }
    
    // ============ Required for receiving NFTs ============
    
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    // Allow contract to receive native tokens
    receive() external payable {}
}