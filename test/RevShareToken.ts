// test/RevShareToken.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { RevShareToken } from "../typechain-types";

describe("RevShareToken", function () {
    let RevShareToken: any;
    let MockERC20: any;
    let revShareToken: RevShareToken;
    let mockERC20: any;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        MockERC20 = await ethers.getContractFactory("MockERC20");
        mockERC20 = await MockERC20.deploy(ethers.parseEther("10000"));

        RevShareToken = await ethers.getContractFactory("RevShareToken");
        revShareToken = await RevShareToken.deploy(
	    "RevShareToken", "RBF", await mockERC20.getAddress());

        await revShareToken.grantRole(await revShareToken.MINTER_ROLE(), owner.address);
        await revShareToken.grantRole(await revShareToken.BURNER_ROLE(), owner.address);
        await revShareToken.grantRole(await revShareToken.DISTRIBUTOR_ROLE(), owner.address);
        await revShareToken.grantRole(await revShareToken.CLAIMER_ROLE(), addr1.address);
    });

    it("should calculate exact distribution amounts", async function () {
        await revShareToken.mint(addr1.address, ethers.parseEther("100"));
        await revShareToken.mint(addr2.address, ethers.parseEther("200"));

        await mockERC20.transfer(await revShareToken.getAddress(), ethers.parseEther("100"));
        await revShareToken.distribute(ethers.parseEther("300"));

        await revShareToken.connect(addr1).claim();
        expect(await mockERC20.balanceOf(addr1.address)).to.equal(ethers.parseEther("100"));
    });

    it("should handle multiple distributions", async function () {
        await revShareToken.mint(addr1.address, ethers.parseEther("100"));

        // First distribution
        await mockERC20.transfer(await revShareToken.getAddress(), ethers.parseEther("100"));
        await revShareToken.distribute(ethers.parseEther("100"));
        await revShareToken.connect(addr1).claim();

        // Second distribution
        await mockERC20.transfer(await revShareToken.getAddress(), ethers.parseEther("200"));
        await revShareToken.distribute(ethers.parseEther("200"));
        await revShareToken.connect(addr1).claim();

        expect(await mockERC20.balanceOf(addr1.address)).to.equal(ethers.parseEther("300"));
    });

    it("should update claims after token transfers", async function () {
        await revShareToken.mint(addr1.address, ethers.parseEther("100"));

        // Initial distribution
        await mockERC20.transfer(await revShareToken.getAddress(), ethers.parseEther("100"));
        await revShareToken.distribute(ethers.parseEther("100"));
        await revShareToken.connect(addr1).claim();

        // Transfer tokens
        await revShareToken.connect(addr1).transfer(addr2.address, ethers.parseEther("50"));

        // Second distribution
        await mockERC20.transfer(await revShareToken.getAddress(), ethers.parseEther("100"));
        await revShareToken.distribute(ethers.parseEther("100"));

        await revShareToken.connect(addr1).claim();
	await revShareToken.grantRole(await revShareToken.CLAIMER_ROLE(), addr2.address);
        await revShareToken.connect(addr2).claim();

        expect(await mockERC20.balanceOf(addr1.address)).to.equal(ethers.parseEther("150"));
        expect(await mockERC20.balanceOf(addr2.address)).to.equal(ethers.parseEther("50"));
    });

    it("should handle claims with burned tokens", async function () {
        await revShareToken.mint(addr1.address, ethers.parseEther("100"));
        await mockERC20.transfer(await revShareToken.getAddress(), ethers.parseEther("50"));
        await revShareToken.distribute(ethers.parseEther("100"));

        await revShareToken.burn(addr1.address, ethers.parseEther("100"));
        await revShareToken.connect(addr1).claim();

        expect(await mockERC20.balanceOf(addr1.address)).to.equal(ethers.parseEther("50"));
    });

    it("should reject zero-value claims", async function () {
        await revShareToken.mint(addr1.address, ethers.parseEther("100"));
        await revShareToken.connect(addr1).claim();
        expect(await mockERC20.balanceOf(addr1.address)).to.equal(0);
    });

    it("should verify pool state after distribution", async function () {
        await revShareToken.mint(addr1.address, ethers.parseEther("100"));
        await mockERC20.transfer(await revShareToken.getAddress(), ethers.parseEther("100"));

        await revShareToken.distribute(ethers.parseEther("300"));
        const totalPool = await revShareToken.totalPool();

        expect(totalPool.tokensDistributed).to.equal(ethers.parseEther("300"));
        expect(totalPool.weightedAverage).to.equal(ethers.parseEther("300") * ethers.parseEther("100"));
    });

    // Keep original access control tests
    it("should fail unauthorized operations", async function () {
        await expect(revShareToken.connect(addr1).mint(addr1.address, 100))
            .to.be.revertedWithCustomError(revShareToken, "AccessControlUnauthorizedAccount");

        await expect(revShareToken.connect(addr1).distribute(100))
            .to.be.revertedWithCustomError(revShareToken, "AccessControlUnauthorizedAccount");

        await expect(revShareToken.connect(addr2).claim())
            .to.be.revertedWithCustomError(revShareToken, "AccessControlUnauthorizedAccount");
    });
});
