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
    const zether = (await deployer.deployZetherVerifier()).contractAddress;
    const burn = (await deployer.deployBurnVerifier()).contractAddress;
    const cash = (await deployer.deployCashToken()).contractAddress;
    await deployer.mintCashToken(cash, 1000);
    const zsc = (await deployer.deployZSC(cash, zether, burn, 6)).contractAddress; // epoch length in seconds.
    await deployer.approveCashToken(cash, zsc, 1000)
    const deployed = new web3.eth.Contract(ZSC.abi, zsc);

    const alice = new Client(web3, deployed, accounts[0]);
    await alice.initialize();
    await alice.deposit(1000);
    await alice.withdraw(100);
    const bob = new Client(web3, deployed, accounts[0]);
    await bob.initialize();
    alice.friends.add("Bob", bob.account.public());
    await alice.transfer('Bob', 100);
};

run().catch(console.error);