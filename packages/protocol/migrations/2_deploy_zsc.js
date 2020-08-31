var InnerProductVerifier = artifacts.require("InnerProductVerifier");
var BurnVerifier = artifacts.require("BurnVerifier");
var ZetherVerifier = artifacts.require("ZetherVerifier");
var CashToken = artifacts.require("CashToken");
var ZSC = artifacts.require("ZSC");

module.exports = (deployer) => {
    return Promise.all([
        deployer.deploy(CashToken),
        deployer.deploy(InnerProductVerifier, { gas: 6721975 }).then(() => Promise.all([
            deployer.deploy(ZetherVerifier, InnerProductVerifier.address, { gas: 6721975 }),
            deployer.deploy(BurnVerifier, InnerProductVerifier.address, { gas: 6721975 })
        ]))
    ]).then(() => deployer.deploy(ZSC, CashToken.address, ZetherVerifier.address, BurnVerifier.address, 6));
}