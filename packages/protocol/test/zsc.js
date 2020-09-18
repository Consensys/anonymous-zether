const CashToken = artifacts.require("CashToken");
const ZSC = artifacts.require("ZSC");
const Client = require('../../anonymous.js/src/client.js');

contract("ZSC", async (accounts) => {
    let alice; // will reuse...

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
    });

    it("should allow funding", async () => {
        await alice.deposit(100);
    });

    it("should allow withdrawing", async () => {
        await alice.withdraw(10);
    });

    it("should allow transferring", async () => {
        const zsc = await ZSC.deployed();
        const bob = new Client(web3, zsc.contract, accounts[0]);
        const carol = new Client(web3, zsc.contract, accounts[0]);
        const dave = new Client(web3, zsc.contract, accounts[0]);
        const miner = new Client(web3, zsc.contract, accounts[0]);
        await Promise.all([bob.register(), carol.register(), dave.register(), miner.register()]);
        alice.friends.add("Bob", bob.account.public());
        alice.friends.add("Carol", carol.account.public());
        alice.friends.add("Dave", dave.account.public());
        alice.friends.add("Miner", miner.account.public());
        await alice.transfer("Bob", 10, ["Carol", "Dave"], "Miner");
        await new Promise((resolve) => setTimeout(resolve, 100));
        assert.equal(
            bob.account.balance(),
            10,
            "Transfer failed"
        );
        const fee = await zsc.fee.call();
        assert.equal(
            miner.account.balance(),
            fee,
            "Fees failed"
        );
    });
});