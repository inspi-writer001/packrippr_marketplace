# PackripprMarketplace

PackripprMarketplace is a specialized smart contract designed for the management and trading of in-game NFT assets. It facilitates primary sales via admin listings and secondary market engagement through user-generated offers.

## Core Features

- **Admin-Controlled Listings**: Only the contract owner can create, update, or cancel listings based on Requirement.
- **Batch Operations**: Supports the simultaneous listing of multiple NFTs to optimize gas efficiency during collection drops.
- **Flexible Payments**: Supports transactions in native currency (ETH) and authorized ERC20 tokens (USDC, ..).
- **Offer System**: Enables users to place time-bound bids on any NFT using ERC20 tokens.

## Contract Methods

### Listing Management (Admin Only)

| Method               | Description                                              |
| -------------------- | -------------------------------------------------------- |
| `createListing`      | Creates a single fixed-price listing for a specific NFT. |
| `batchListNFTs`      | Creates multiple listings in a single transaction.       |
| `updateListingPrice` | Modifies the price of an existing active listing.        |
| `cancelListing`      | Removes an active listing from the marketplace.          |

### Trading (Public)

| Method        | Description                                                           |
| ------------- | --------------------------------------------------------------------- |
| `buyListing`  | Executes an immediate purchase of a listed NFT.                       |
| `createOffer` | Allows a user to bid on an NFT with a specified expiration time.      |
| `cancelOffer` | Permits the offer creator to retract their bid before it is accepted. |
| `acceptOffer` | Allows the NFT owner to accept a buyer's offer, triggering the swap.  |

### Configuration (Admin Only)

| Method                   | Description                                                      |
| ------------------------ | ---------------------------------------------------------------- |
| `setFeePercent`          | Updates the marketplace transaction fee (max 10%).               |
| `setFeeRecipient`        | Designates the address that receives collected marketplace fees. |
| `setAllowedPaymentToken` | Manages the list of tokens accepted for trades and offers.       |

## Technical Details

### Security

The contract utilizes OpenZeppelin's `ReentrancyGuard` to prevent reentrancy attacks and `Ownable` for secure access control. High-value state changes are emitted via events for off-chain indexing.

### Fees

Marketplace fees are calculated using basis points (e.g., 250 bps = 2.5%). Fees are automatically deducted from the sale price and routed to the fee recipient during successful trades.

### Integrations

- **ERC721**: The contract interacts with standard NFT implementations.
- **ERC20**: Used for both payments and the escrow-less offer system.
