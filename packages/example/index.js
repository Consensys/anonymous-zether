const Web3 = require("web3");
const Client = require("../anonymous.js/src/client.js");
const ZSC = require("../contract-artifacts/artifacts/ZSC.json");
const Deployer = require('./deployer.js');
const Provider = require('./provider.js');
const utils = require('../anonymous.js/src/utils/utils.js');

const run = async () => {
    var provider = new Provider("ws://localhost:23000");
    const web3 = new Web3(await provider.getProvider());
    const accounts = await web3.eth.getAccounts();

    var deployer = new Deployer(accounts);
    const [
        cash, [zether, burn]
    ] = await Promise.all([deployer.deployCashToken().then((result) => result.contractAddress), deployer.deployInnerProductVerifier().then((result) => {
        ip = result.contractAddress;
        return Promise.all([deployer.deployZetherVerifier(ip), deployer.deployBurnVerifier(ip)]).then((results) => results.map((result) => result.contractAddress));
    })]);

    const zsc = await Promise.all([deployer.deployZSC(cash, zether, burn, 6), deployer.mintCashToken(cash, 1000)]).then((results) => results[0].contractAddress);
    await deployer.approveCashToken(cash, zsc, 1000);
    const deployed = new web3.eth.Contract(ZSC.abi, zsc);

    const alice = new Client(web3, deployed, accounts[0]);
    await alice.register();
    await alice.deposit(100);
    await alice.withdraw(10);
    const bob = new Client(web3, deployed, accounts[0]);
    await bob.register();
    alice.friends.add("Bob", bob.account.public());
    await alice.transfer('Bob', 10);
};

run().catch(console.error);