// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GameMarketplace
 * @notice Simple marketplace for in-game NFT trading with offers support
 * @dev Supports both instant buy listings and offers (bids)
 */
contract GameMarketplace is ReentrancyGuard, Ownable {
    
    // ============ Structs ============
    
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        address paymentToken; // address(0) for native token (ETH/MATIC)
        uint256 price;
        bool active;
    }
    
    struct Offer {
        address buyer;
        address nftContract;
        uint256 tokenId;
        address paymentToken;
        uint256 price;
        uint256 expiresAt;
        bool active;
    }
    
    // ============ State Variables ============
    
    // listingId => Listing
    mapping(uint256 => Listing) public listings;
    uint256 public nextListingId;
    
    // offerId => Offer
    mapping(uint256 => Offer) public offers;
    uint256 public nextOfferId;
    
    // nftContract => tokenId => listingId (for quick lookup)
    mapping(address => mapping(uint256 => uint256)) public tokenToListing;
    
    // Marketplace fee (in basis points, 250 = 2.5%)
    uint256 public feePercent = 250;
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    // Fee recipient
    address public feeRecipient;
    
    // Allowed payment tokens (address(0) = native token)
    mapping(address => bool) public allowedPaymentTokens;
    
    // ============ Events ============
    
    event Listed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price
    );
    
    event ListingCancelled(uint256 indexed listingId);
    
    event ListingUpdated(uint256 indexed listingId, uint256 newPrice);
    
    event Sold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );
    
    event OfferCreated(
        uint256 indexed offerId,
        address indexed buyer,
        address indexed nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 expiresAt
    );
    
    event OfferCancelled(uint256 indexed offerId);
    
    event OfferAccepted(
        uint256 indexed offerId,
        address indexed seller,
        address indexed buyer,
        address nftContract,
        uint256 tokenId,
        uint256 price
    );
    
    event FeePercentUpdated(uint256 newFeePercent);
    event FeeRecipientUpdated(address newFeeRecipient);
    event PaymentTokenUpdated(address token, bool allowed);
    
    // ============ Constructor ============
    
    constructor(address _feeRecipient, address _initialOwner) Ownable(_initialOwner) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
        
        // Allow native token by default
        allowedPaymentTokens[address(0)] = true;
    }
    
    // ============ Listing Functions ============
    
    /**
     * @notice Create a new listing for an NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to list
     * @param paymentToken Address of payment token (address(0) for native)
     * @param price Listing price
     */
    function createListing(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price
    ) external nonReentrant returns (uint256) {
        require(price > 0, "Price must be > 0");
        require(allowedPaymentTokens[paymentToken], "Payment token not allowed");
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "Not token owner"
        );
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "Marketplace not approved"
        );
        require(
            tokenToListing[nftContract][tokenId] == 0,
            "Already listed"
        );
        
        uint256 listingId = ++nextListingId;
        
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentToken: paymentToken,
            price: price,
            active: true
        });
        
        tokenToListing[nftContract][tokenId] = listingId;
        
        emit Listed(listingId, msg.sender, nftContract, tokenId, paymentToken, price);
        
        return listingId;
    }
    
    /**
     * @notice Cancel a listing
     * @param listingId ID of the listing to cancel
     */
    function cancelListing(uint256 listingId) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller == msg.sender, "Not seller");
        
        listing.active = false;
        tokenToListing[listing.nftContract][listing.tokenId] = 0;
        
        emit ListingCancelled(listingId);
    }
    
    /**
     * @notice Update listing price
     * @param listingId ID of the listing
     * @param newPrice New price
     */
    function updateListingPrice(uint256 listingId, uint256 newPrice) external nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(listing.seller == msg.sender, "Not seller");
        require(newPrice > 0, "Price must be > 0");
        
        listing.price = newPrice;
        
        emit ListingUpdated(listingId, newPrice);
    }
    
    /**
     * @notice Buy a listed NFT
     * @param listingId ID of the listing to buy
     */
    function buyListing(uint256 listingId) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(
            IERC721(listing.nftContract).ownerOf(listing.tokenId) == listing.seller,
            "Seller no longer owns token"
        );
        
        uint256 price = listing.price;
        address seller = listing.seller;
        
        // Calculate fees
        uint256 fee = (price * feePercent) / FEE_DENOMINATOR;
        uint256 sellerAmount = price - fee;
        
        // Transfer payment
        if (listing.paymentToken == address(0)) {
            // Native token (ETH/MATIC)
            require(msg.value >= price, "Insufficient payment");
            
            // Send to seller
            (bool successSeller, ) = payable(seller).call{value: sellerAmount}("");
            require(successSeller, "Transfer to seller failed");
            
            // Send fee
            if (fee > 0) {
                (bool successFee, ) = payable(feeRecipient).call{value: fee}("");
                require(successFee, "Fee transfer failed");
            }
            
            // Refund excess
            if (msg.value > price) {
                (bool successRefund, ) = payable(msg.sender).call{value: msg.value - price}("");
                require(successRefund, "Refund failed");
            }
        } else {
            // ERC20 token
            IERC20 token = IERC20(listing.paymentToken);
            require(
                token.transferFrom(msg.sender, seller, sellerAmount),
                "Transfer to seller failed"
            );
            if (fee > 0) {
                require(
                    token.transferFrom(msg.sender, feeRecipient, fee),
                    "Fee transfer failed"
                );
            }
        }
        
        // Transfer NFT
        IERC721(listing.nftContract).safeTransferFrom(
            seller,
            msg.sender,
            listing.tokenId
        );
        
        // Mark as inactive
        listing.active = false;
        tokenToListing[listing.nftContract][listing.tokenId] = 0;
        
        emit Sold(listingId, msg.sender, seller, listing.nftContract, listing.tokenId, price);
    }
    
    // ============ Offer Functions ============
    
    /**
     * @notice Create an offer for an NFT
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID to make offer for
     * @param paymentToken Address of payment token (must be ERC20, not native)
     * @param price Offer price
     * @param duration How long the offer is valid (in seconds)
     */
    function createOffer(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 price,
        uint256 duration
    ) external nonReentrant returns (uint256) {
        require(price > 0, "Price must be > 0");
        require(paymentToken != address(0), "Use ERC20 for offers");
        require(allowedPaymentTokens[paymentToken], "Payment token not allowed");
        require(duration > 0 && duration <= 90 days, "Invalid duration");
        
        // Check buyer has approved tokens
        IERC20 token = IERC20(paymentToken);
        require(
            token.allowance(msg.sender, address(this)) >= price,
            "Insufficient token approval"
        );
        require(
            token.balanceOf(msg.sender) >= price,
            "Insufficient token balance"
        );
        
        uint256 offerId = ++nextOfferId;
        uint256 expiresAt = block.timestamp + duration;
        
        offers[offerId] = Offer({
            buyer: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentToken: paymentToken,
            price: price,
            expiresAt: expiresAt,
            active: true
        });
        
        emit OfferCreated(offerId, msg.sender, nftContract, tokenId, paymentToken, price, expiresAt);
        
        return offerId;
    }
    
    /**
     * @notice Cancel an offer
     * @param offerId ID of the offer to cancel
     */
    function cancelOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.active, "Offer not active");
        require(offer.buyer == msg.sender, "Not offer creator");
        
        offer.active = false;
        
        emit OfferCancelled(offerId);
    }
    
    /**
     * @notice Accept an offer (seller accepts buyer's offer)
     * @param offerId ID of the offer to accept
     */
    function acceptOffer(uint256 offerId) external nonReentrant {
        Offer storage offer = offers[offerId];
        require(offer.active, "Offer not active");
        require(block.timestamp <= offer.expiresAt, "Offer expired");
        require(
            IERC721(offer.nftContract).ownerOf(offer.tokenId) == msg.sender,
            "Not token owner"
        );
        require(
            IERC721(offer.nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(offer.nftContract).getApproved(offer.tokenId) == address(this),
            "Marketplace not approved"
        );
        
        uint256 price = offer.price;
        address buyer = offer.buyer;
        
        // Calculate fees
        uint256 fee = (price * feePercent) / FEE_DENOMINATOR;
        uint256 sellerAmount = price - fee;
        
        // Transfer payment from buyer
        IERC20 token = IERC20(offer.paymentToken);
        require(
            token.transferFrom(buyer, msg.sender, sellerAmount),
            "Transfer to seller failed"
        );
        if (fee > 0) {
            require(
                token.transferFrom(buyer, feeRecipient, fee),
                "Fee transfer failed"
            );
        }
        
        // Transfer NFT to buyer
        IERC721(offer.nftContract).safeTransferFrom(
            msg.sender,
            buyer,
            offer.tokenId
        );
        
        // Mark as inactive
        offer.active = false;
        
        // Cancel any listing for this token
        uint256 listingId = tokenToListing[offer.nftContract][offer.tokenId];
        if (listingId != 0 && listings[listingId].active) {
            listings[listingId].active = false;
            tokenToListing[offer.nftContract][offer.tokenId] = 0;
        }
        
        emit OfferAccepted(offerId, msg.sender, buyer, offer.nftContract, offer.tokenId, price);
    }
    
    // ============ Admin Functions ============
    
    /**
     * @notice Update marketplace fee percentage
     * @param newFeePercent New fee in basis points (250 = 2.5%)
     */
    function setFeePercent(uint256 newFeePercent) external onlyOwner {
        require(newFeePercent <= 1000, "Fee too high"); // Max 10%
        feePercent = newFeePercent;
        emit FeePercentUpdated(newFeePercent);
    }
    
    /**
     * @notice Update fee recipient address
     * @param newFeeRecipient New fee recipient
     */
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid address");
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }
    
    /**
     * @notice Set whether a payment token is allowed
     * @param token Token address (address(0) for native)
     * @param allowed Whether the token is allowed
     */
    function setAllowedPaymentToken(address token, bool allowed) external onlyOwner {
        allowedPaymentTokens[token] = allowed;
        emit PaymentTokenUpdated(token, allowed);
    }
    
    // ============ View Functions ============
    
    /**
     * @notice Get listing details
     * @param listingId Listing ID
     */
    function getListing(uint256 listingId) external view returns (Listing memory) {
        return listings[listingId];
    }
    
    /**
     * @notice Get offer details
     * @param offerId Offer ID
     */
    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }
    
    /**
     * @notice Check if a token is currently listed
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     */
    function isListed(address nftContract, uint256 tokenId) external view returns (bool) {
        uint256 listingId = tokenToListing[nftContract][tokenId];
        return listingId != 0 && listings[listingId].active;
    }
    
    /**
     * @notice Get listing ID for a token
     * @param nftContract NFT contract address
     * @param tokenId Token ID
     */
    function getListingByToken(address nftContract, uint256 tokenId) external view returns (uint256) {
        return tokenToListing[nftContract][tokenId];
    }
    
    // Required for receiving NFTs
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}