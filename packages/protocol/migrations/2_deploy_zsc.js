var InnerProductVerifier = artifacts.require("InnerProductVerifier");
var BurnVerifier = artifacts.require("BurnVerifier");
var ZetherVerifier = artifacts.require("ZetherVerifier");
var CashToken = artifacts.require("CashToken");
var ZSC = artifacts.require("ZSC");

// Using first two addresses of Ganache
module.exports = (deployer) => {
    return Promise.all([deployer.deploy(CashToken).then((result) => result.contractAddress), deployer.deploy(InnerProductVerifier, { gas: 4700000 })
        .then(() => Promise.all([deployer.deploy(ZetherVerifier, InnerProductVerifier.address, { gas: 8000000 }), deployer.deploy(BurnVerifier, InnerProductVerifier.address, { gas: 4700000 })]))
    ]).then(() => deployer.deploy(ZSC, CashToken.address, ZetherVerifier.address, BurnVerifier.address, 6));
}