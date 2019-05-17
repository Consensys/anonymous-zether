const Web3 = require("web3");
const Client = require("../anonymous.js/src/client");
const ZSC = require("../contract-artifacts/artifacts/ZSC.json");
const getProvider = require("./provider");
const methods = require('./contract');
const net = require('net');

const sleep = (time) => new Promise(resolve => setTimeout(resolve, time));

(async () => {
    const provider = await getProvider(); // for websockets
    const web3 = new Web3(provider);

    web3.transactionConfirmationBlocks = 1;
    const zvReceipt = await methods.DeployZV();
    const bvReceipt = await methods.DeployBV();
    const erc20Receipt = await methods.DeployERC20()
    await methods.MintERC20(erc20Receipt.contractAddress);
    const zscReceipt = await methods.DeployZSC(erc20Receipt.contractAddress, zvReceipt.contractAddress, bvReceipt.contractAddress, 3000);
    await methods.ApproveERC20(erc20Receipt.contractAddress, zscReceipt.contractAddress)
    const deployedZSC = new web3.eth.Contract(
        ZSC.abi,
        zscReceipt.contractAddress
    );

    const accounts = await web3.eth.getAccounts();
    const client = new Client(deployedZSC, accounts[0], web3);
    await client.account.initialize();
    client.friends.addFriend("Alice", ['0x0eaadaaa84784811271240ec2f03b464015082426aa13a46a99a56c964a5c7cc', '0x173ce032ad098e9fcbf813696da92328257e58827f3600b259c42e52ff809433']);
    client.friends.showFriends();
    client.deposit(10000);
    await sleep(4000);
    client.withdraw(1000);
    await sleep(4000);
    client.transfer('Alice', 1000)
})();