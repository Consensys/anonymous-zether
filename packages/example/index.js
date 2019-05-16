const Web3 = require("web3");
const Client = require("../anonymous.js/src/client");
const ZSC = require("../contract-artifacts/artifacts/ZSC.json");
const getProvider = require("./provider");
const methods = require('./contract');

const sleep = () => new Promise(resolve => setTimeout(resolve, 5000));

(async () => {
  const provider = await getProvider(); // for websockets
  const web3Socket = new Web3(provider);
  web3Socket.transactionConfirmationBlocks = 1;
  const zvReceipt = await methods.DeployZV();
  const bvReceipt = await methods.DeployBV();
  const erc20Receipt = await methods.DeployERC20()
  await methods.MintERC20(erc20Receipt.contractAddress);
  const zscReceipt = await methods.DeployZSC(zvReceipt.contractAddress, bvReceipt.contractAddress, erc20Receipt.contractAddress);
  await methods.ApproveERC20(erc20Receipt.contractAddress, zscReceipt.contractAddress)
  const deployedZSC = new web3Socket.eth.Contract(
    ZSC.abi,
    zscReceipt.contractAddress
  );

  const account = await web3Socket.eth.getAccounts();
  const client = new Client(deployedZSC, account[0], web3Socket);
  await client.account.initialize();
  client.friends.addFriend("alice",[ '0x0eaadaaa84784811271240ec2f03b464015082426aa13a46a99a56c964a5c7cc','0x173ce032ad098e9fcbf813696da92328257e58827f3600b259c42e52ff809433' ]);
  const friends = client.friends.showFriends();
  client.deposit(3000);
  client.withdraw(1000);
})();
