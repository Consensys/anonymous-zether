const { ethers } = require("hardhat");
const { expect } = require("chai");
const Client = require('../../anonymous.js/src/client.js');
const Web3 = require('web3');
// const { ethers } = require('hardhat');
describe("Token contract", function () {
    let alice; // will reuse...
    let bob;
    let carol;
    let dave;
    let miner;
    let cashToken;
    it("Deployment should assign the total supply of tokens to the owner", async function () {
        const [owner] = await ethers.getSigners();

        const CashTokenConstract = await ethers.getContractFactory("CashToken");

        cashToken = await CashTokenConstract.deploy();
        const ownerBalance = await cashToken.balanceOf(owner.address);
        expect(await cashToken.totalSupply()).to.equal(ownerBalance);
    });
    it("should allow minting and approving", async () => {
        const [owner] = await ethers.getSigners();
        const InnerProductVerifier = await ethers.getContractFactory("InnerProductVerifier");
        const innerProductVerifier = await InnerProductVerifier.deploy();
        const BurnVerifier = await ethers.getContractFactory("BurnVerifier");
        const burnVerifier = await BurnVerifier.deploy(innerProductVerifier.address);
        const ZetherVerifier = await ethers.getContractFactory("ZetherVerifier");
        const zetherVerifier = await ZetherVerifier.deploy(innerProductVerifier.address);
        const zscConstract = await ethers.getContractFactory("ZSC");
        const zsc = await zscConstract.deploy(cashToken.address, zetherVerifier.address, burnVerifier.address, 10);
        await cashToken.mint(owner.address, 1000);
        await cashToken.approve(zsc.address, 1000);
        const web3 = new Web3('http://localhost:8545');
        alice = new Client(web3, zsc, owner);
        await alice.register();
    });
});