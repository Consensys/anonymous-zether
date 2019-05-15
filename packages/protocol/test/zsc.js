const CashToken = artifacts.require("CashToken");
const ZSC = artifacts.require("ZSC");
const maintenance = require('../src/utils/maintenance.js');

contract("ZSC", async accounts => {
    it("should allow depositing / funding", async () => {
        let cash = await CashToken.deployed();
        let zsc = await ZSC.deployed();
        await cash.mint(accounts[0], 10000000);
        let balance = await cash.balanceOf.call(accounts[0]);
        assert.equal(
            balance,
            10000000,
            "Minting failed."
        );
        var y = maintenance.createAccount()['y'];
        var resp = await zsc.register(y);
        var receipt = await web3.eth.getTransactionReceipt(resp.tx);
        assert.equal(
            receipt.status,
            "0x1",
            "Registration failed."
        ); // this might be necessary.
    });
});