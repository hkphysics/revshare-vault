// test/RevShareToken.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("RevShareToken", function () {
    let RevShareToken: any;
    let MockERC20: any;
    let revShareToken: any;
    let mockERC20: any;
    let owner: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();

        // Deploy the mock ERC20 token
        MockERC20 = await ethers.getContractFactory("MockERC20");
        mockERC20 = await MockERC20.deploy(ethers.parseEther("10000"));

        // Deploy the RevShareToken contract
        RevShareToken = await ethers.getContractFactory("RevShareToken");
        revShareToken = await RevShareToken.deploy(await mockERC20.getAddress());
        
        // Grant roles
        await revShareToken.grantRole(await revShareToken.MINTER_ROLE(), await owner.getAddress());
        await revShareToken.grantRole(await revShareToken.BURNER_ROLE(), await owner.getAddress());
        await revShareToken.grantRole(await revShareToken.DISTRIBUTE_ROLE(), await owner.getAddress());
        await revShareToken.grantRole(await revShareToken.CLAIM_ROLE(), await addr1.getAddress());
    });

    it("should allow minting tokens", async function () {
        await revShareToken.mint(await addr1.getAddress(), ethers.parseEther("100"));
        expect(await revShareToken.balanceOf(await addr1.getAddress())).to.equal(ethers.parseEther("100"));
    });

    it("should allow burning tokens", async function () {
        await revShareToken.mint(await addr1.getAddress(), ethers.parseEther("100"));
        await revShareToken.burn(await addr1.getAddress(), ethers.parseEther("50"));
        expect(await revShareToken.balanceOf(await addr1.getAddress())).to.equal(ethers.parseEther("50"));
    });

    it("should distribute tokens correctly", async function () {
        await revShareToken.mint(await addr1.getAddress(), ethers.parseEther("100"));
        await revShareToken.mint(await addr2.getAddress(), ethers.parseEther("200"));

        await mockERC20.transfer(await revShareToken.getAddress(), ethers.parseEther("100"));
        await revShareToken.distribute(ethers.parseEther("300"));        
        await revShareToken.connect(addr1).claim();
        expect(await mockERC20.balanceOf(await addr1.getAddress())).to.be.above(0);
    });
    
    it("should fail if a non-role account tries to mint", async function () {
        await expect(revShareToken.connect(addr1).mint(await addr1.getAddress(), ethers.parseEther("100")))
            .to.be.revertedWithCustomError(revShareToken, "AccessControlUnauthorizedAccount");
    });

    it("should fail if a non-role account tries to distribute tokens", async function () {
        await expect(revShareToken.connect(addr1).distribute(ethers.parseEther("100")))
            .to.be.revertedWithCustomError(revShareToken, "AccessControlUnauthorizedAccount");
    });

    it("should fail if a non-role account tries to claim tokens", async function () {
        await expect(revShareToken.connect(addr2).claim())
            .to.be.revertedWithCustomError(revShareToken, "AccessControlUnauthorizedAccount");
    });
});
