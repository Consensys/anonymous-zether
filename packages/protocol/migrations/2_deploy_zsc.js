var BurnVerifier = artifacts.require("BurnVerifier");
var ZetherVerifier = artifacts.require("ZetherVerifier");
var CashToken = artifacts.require("CashToken");
var ZSC = artifacts.require("ZSC");

// Using first two addresses of Ganache
module.exports = function(deployer) {
    deployer.deploy(CashToken).then(() => {
        return deployer.deploy(ZetherVerifier, { gas: 470000000 });
    }).then(() => {
        return deployer.deploy(BurnVerifier, { gas: 470000000 });
    }).then(() => {
        return deployer.deploy(ZSC, CashToken.address, ZetherVerifier.address, BurnVerifier.address, 6);
    });
}