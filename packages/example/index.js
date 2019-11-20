const Web3 = require("web3");
const Client = require("../anonymous.js/src/client.js");
const ZSC = require("../contract-artifacts/artifacts/ZSC.json");
const Deployer = require('./deployer.js');
const Provider = require('./provider.js');
const utils = require('../anonymous.js/src/utils/utils.js');

const run = async () => {
    var provider = new Provider("ws://localhost:23000");
    const web3 = new Web3(await provider.getProvider());

    web3.transactionConfirmationBlocks = 1;
    var deployer = new Deployer();
    const zether = (await deployer.deployZetherVerifier()).contractAddress;
    const burn = (await deployer.deployBurnVerifier()).contractAddress;
    const cash = (await deployer.deployCashToken()).contractAddress;
    await deployer.mintCashToken(cash);
    const zsc = (await deployer.deployZSC(cash, zether, burn, 6)).contractAddress; // epoch length in seconds.
    await deployer.approveCashToken(cash, zsc)
    const deployed = new web3.eth.Contract(ZSC.abi, zsc);

    const accounts = await web3.eth.getAccounts();
    const alice = new Client(deployed, accounts[0], web3);
    await alice.initialize();
    await alice.deposit(10000);
    await alice.withdraw(1000);
    alice.friends.add("Bob", utils.createAccount()['y']);
    await alice.transfer('Bob', 1000);
};

run().catch(console.error);