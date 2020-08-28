const CashToken = artifacts.require("CashToken");
const ZSC = artifacts.require("ZSC");
const utils = require('../../anonymous.js/src/utils/utils.js');
const Client = require('../../anonymous.js/src/client.js');

contract("ZSC", async (accounts) => {
    let alice;
    let bob;

    it("should allow minting and approving", async () => {
        const cash = await CashToken.deployed();
        const zsc = await ZSC.deployed();
        await cash.mint(accounts[0], 1000);
        await cash.approve(zsc.contract._address, 1000);
        const balance = await cash.balanceOf.call(accounts[0]);
        assert.equal(
            balance,
            1000,
            "Minting failed"
        );
    });

    it("should allow initialization", async () => {
        const zsc = await ZSC.deployed();
        alice = new Client(web3, zsc.contract, accounts[0]);
        await alice.register();
        assert.exists(
            alice._epochLength,
            "Initialization failed"
        );
    });

    it("should allow funding", async () => {
        await alice.deposit(100);
    });

    it("should allow withdrawing", async () => {
        await alice.withdraw(10);
    });

    it("should allow transferring", async () => {
        const zsc = await ZSC.deployed();
        bob = new Client(web3, zsc.contract, accounts[0]);
        await bob.register();
        alice.friends.add("Bob", bob.account.public());
        await alice.transfer("Bob", 10);
        // bob won't actually receive the transfer, because truffle uses HttpProvider
        // can't use websocket providers at this point, because of geth bugs. will fix
        // https://github.com/trufflesuite/truffle/issues/1699
    });
});
