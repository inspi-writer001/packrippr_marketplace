import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer, parseEther, ZeroAddress } from "ethers";
import { PackripprMarketplace, PackripprNFT, MockERC20 } from "../typechain-types";

describe("PackripprMarketplace", function () {
  let marketplace: PackripprMarketplace;
  let nft: PackripprNFT;
  let paymentToken: MockERC20;
  let owner: Signer;
  let user: Signer;
  let feeRecipient: Signer;

  const FEE_PERCENT = 250; // 2.5%

  beforeEach(async function () {
    [owner, user, feeRecipient] = await ethers.getSigners();

    // 1. Deploy Mock ERC20 for payments
    const ERC20Factory = await ethers.getContractFactory("MockERC20");
    paymentToken = await ERC20Factory.deploy("USDC", "USDC");

    // 2. Deploy NFT Contract
    const NFTFactory = await ethers.getContractFactory("PackripprNFT");
    nft = await NFTFactory.deploy("Packrippr Cards", "PACK", await feeRecipient.getAddress(), 500);

    // 3. Deploy Marketplace
    const MarketplaceFactory = await ethers.getContractFactory("PackripprMarketplace");
    marketplace = await MarketplaceFactory.deploy(await feeRecipient.getAddress(), await owner.getAddress());

    // 4. Setup permissions
    await marketplace.setAllowedPaymentToken(await paymentToken.getAddress(), true);
    await nft.setApprovalForAll(await marketplace.getAddress(), true);
    await nft.connect(user).setApprovalForAll(await marketplace.getAddress(), true);

    // 5. Fund user with tokens
    await paymentToken.mint(await user.getAddress(), parseEther("1000"));
    await paymentToken.connect(user).approve(await marketplace.getAddress(), parseEther("1000"));
  });

  describe("Hybrid Listing Logic (Toggle)", function () {
    it("Should allow Owner to list when publicListingEnabled is false", async function () {
      await nft.safeMint(await owner.getAddress(), "uri1");
      await expect(marketplace.createListing(await nft.getAddress(), 0, ZeroAddress, parseEther("1")))
        .to.emit(marketplace, "Listed");
    });

    it("Should prevent regular users from listing when publicListingEnabled is false", async function () {
      await nft.safeMint(await user.getAddress(), "uri1");
      await expect(marketplace.connect(user).createListing(await nft.getAddress(), 0, ZeroAddress, parseEther("1")))
        .to.be.revertedWith("Marketplace: Public listing is disabled");
    });

    it("Should allow regular users to list when publicListingEnabled is true", async function () {
      await marketplace.togglePublicListing(true);
      await nft.safeMint(await user.getAddress(), "uri1");
      await expect(marketplace.connect(user).createListing(await nft.getAddress(), 0, ZeroAddress, parseEther("1")))
        .to.emit(marketplace, "Listed");
    });
  });

  describe("Trading Flow", function () {
    beforeEach(async function () {
      await nft.safeMint(await owner.getAddress(), "uri1");
      await marketplace.createListing(await nft.getAddress(), 0, await paymentToken.getAddress(), parseEther("100"));
    });

    it("Should execute a purchase and distribute fees correctly", async function () {
      const sellerBalanceBefore = await paymentToken.balanceOf(await owner.getAddress());
      const feeRecipientBalanceBefore = await paymentToken.balanceOf(await feeRecipient.getAddress());

      await marketplace.connect(user).buyListing(1);

      // Verify NFT transfer
      expect(await nft.ownerOf(0)).to.equal(await user.getAddress());

      // Verify Payments (Price 100, Fee 2.5)
      expect(await paymentToken.balanceOf(await owner.getAddress())).to.equal(sellerBalanceBefore + parseEther("97.5"));
      expect(await paymentToken.balanceOf(await feeRecipient.getAddress())).to.equal(feeRecipientBalanceBefore + parseEther("2.5"));
    });
  });

  describe("Offer System", function () {
    it("Should allow users to create and owners to accept offers", async function () {
      await nft.safeMint(await owner.getAddress(), "uri1");
      
      // User makes an offer for 50 USDC
      await marketplace.connect(user).createOffer(await nft.getAddress(), 0, await paymentToken.getAddress(), parseEther("50"), 86400);
      
      const userBalanceBefore = await paymentToken.balanceOf(await user.getAddress());
      
      await marketplace.acceptOffer(1);

      expect(await nft.ownerOf(0)).to.equal(await user.getAddress());
      expect(await paymentToken.balanceOf(await user.getAddress())).to.equal(userBalanceBefore - parseEther("50"));
    });
  });

  describe("Listing Management", function () {
    it("Should allow users to cancel their own listings", async function () {
      await marketplace.togglePublicListing(true);
      await nft.safeMint(await user.getAddress(), "uri1");
      await marketplace.connect(user).createListing(await nft.getAddress(), 0, ZeroAddress, parseEther("1"));
      
      await expect(marketplace.connect(user).cancelListing(1))
        .to.emit(marketplace, "ListingCancelled");
    });

    it("Should allow users to update their own listing prices", async function () {
      await marketplace.togglePublicListing(true);
      await nft.safeMint(await user.getAddress(), "uri1");
      await marketplace.connect(user).createListing(await nft.getAddress(), 0, ZeroAddress, parseEther("1"));
      
      await expect(marketplace.connect(user).updateListingPrice(1, parseEther("2")))
        .to.emit(marketplace, "ListingUpdated")
        .withArgs(1, parseEther("2"));
    });
  });
});