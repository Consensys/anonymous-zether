const CashToken = artifacts.require("CashToken");
const ZSC = artifacts.require("ZSC");
const Client = require('../../anonymous.js/src/client.js');

contract("ZSC", async (accounts) => {
    let alice; // will reuse...
    let bob;
    let carol;
    let dave;
    let miner;

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

    it("should allow transferring (2 decoys and miner)", async () => {
        const zsc = await ZSC.deployed();
        bob = new Client(web3, zsc.contract, accounts[0]);
        carol = new Client(web3, zsc.contract, accounts[0]);
        dave = new Client(web3, zsc.contract, accounts[0]);
        miner = new Client(web3, zsc.contract, accounts[0]);
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

    it("should allow transferring (2 decoys and NO miner)", async () => {
        const zsc = await ZSC.deployed();
        await alice.transfer("Bob", 10, ["Carol", "Dave"]);
        await new Promise((resolve) => setTimeout(resolve, 100));
        assert.equal(
            bob.account.balance(),
            20,
            "Transfer failed"
        );
    });

    it("should allow transferring (6 decoys and miner)", async () => {
        const zsc = await ZSC.deployed();
        bob1 = new Client(web3, zsc.contract, accounts[0]);
        carol1 = new Client(web3, zsc.contract, accounts[0]);
        dave1 = new Client(web3, zsc.contract, accounts[0]);
        miner1 = new Client(web3, zsc.contract, accounts[0]);
        await Promise.all([bob1.register(), carol1.register(), dave1.register(), miner1.register()]);
        alice.friends.add("Bob1", bob1.account.public());
        alice.friends.add("Carol1", carol1.account.public());
        alice.friends.add("Dave1", dave1.account.public());
        alice.friends.add("Miner1", miner1.account.public());
        await alice.transfer("Bob", 10, ["Carol", "Dave", "Bob1", "Carol1", "Dave1", "Miner1"], "Miner");
        await new Promise((resolve) => setTimeout(resolve, 100));
        assert.equal(
            bob.account.balance(),
            30,
            "Transfer failed"
        );
        const fee = await zsc.fee.call();
        assert.equal(
            miner.account.balance(),
            fee,
            "Fees failed"
        );
    });

    it("should allow transferring without decoys or miner", async () => {
        const zsc = await ZSC.deployed();
        zuza = new Client(web3, zsc.contract, accounts[0]);
        await zuza.register()
        alice.friends.add("Zuza", zuza.account.public());
        await alice.transfer("Zuza", 5);
        await new Promise((resolve) => setTimeout(resolve, 100));
        assert.equal(
            zuza.account.balance(),
            5,
            "Transfer failed"
        );
    });

    it("should allow transferring without decoys but with miner", async () => {
        await alice.transfer("Carol", 5, [], "Miner");
        await new Promise((resolve) => setTimeout(resolve, 100));
        assert.equal(
            carol.account.balance(),
            5,
            "Transfer failed"
        );
    });

});