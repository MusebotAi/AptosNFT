const {
    loadFixture,
  } = require("@nomicfoundation/hardhat-network-helpers");
  const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
  const { expect } = require("chai");
  
  describe("MusebotAi", function() {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function deployMintOneFixture() {
  
      // Contracts are deployed using the first signer/account by default
      const [owner, otherAccount] = await ethers.getSigners();
  
      const MintOne = await hre.ethers.getContractFactory("MusebotAi");
      const mintOne = await MintOne.deploy(await owner.getAddress());

      return { mintOne, owner, otherAccount };
    }
  
    describe("Deployment", function () {
      it("Should set the right name", async function () {
        const { mintOne } = await loadFixture(deployMintOneFixture);
  
        expect(await mintOne.name()).to.equal("MuseToken");
      });
    });
  
    describe("Mint", function () {
      describe("Validations", function () {
        it("mint one and check account", async function () {
            const { mintOne, otherAccount } = await loadFixture(deployMintOneFixture);
            let uri = "https://stacktrace.top/imags/1.json";
            let tokenId = await mintOne.connect(otherAccount).mintOne(uri);

            let addr = await otherAccount.getAddress();
            tokenId = Number((await tokenId.wait()).events[0].args.tokenId);
            expect(await mintOne.balanceOf(addr)).to.equal(1);
            let nUri = await mintOne.tokenURI(tokenId);
            console.log(nUri);
            expect(uri).to.equal(nUri);

            await expect(mintOne.connect(otherAccount).mintOne(uri))
            .to.emit(mintOne, "Transfer")
            .withArgs('0x0000000000000000000000000000000000000000',addr, tokenId+1); // We accept any value as `when` arg
        });
      });
    });
  });
  