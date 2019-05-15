const AZ = require("./src");
const Web3 = require("web3");
const ZV = require("../contract-artifacts/artifacts/ZetherVerifier.json");
const BV = require("../contract-artifacts/artifacts/BurnVerifier.json");
const ERC20 = require("../contract-artifacts/artifacts/ERC20Interface.json");
const ZSC = require("../contract-artifacts/artifacts/ZSC.json");
const Client = require("./src/client");
const getProvider = require("./provider");

(async () => {
  const provider = await getProvider(); // for websockets
  const web3 = new Web3(
    new Web3.providers.HttpProvider("http://localhost:22000")
  );
  const web3Socket = new Web3(provider);
  web3.transactionConfirmationBlocks = 1;
  const zvAbi = ZV.abi;
  const zvBytecode = ZV.bytecode;
  const zvContract = new web3.eth.Contract(zvAbi);

  const bvAbi = BV.abi;
  const bvBytecode = BV.bytecode;
  const bvContract = new web3.eth.Contract(bvAbi);

  const erc20Abi = ERC20.abi;
  const erc20Bytecode = ERC20.bytecode;
  const erc20Contract = new web3.eth.Contract(erc20Abi);

  const zscAbi = ZSC.abi;
  const zscBytecode = ZSC.bytecode;
  const zscContract = new web3.eth.Contract(zscAbi);

  zvContract
    .deploy({
      data: zvBytecode
    })
    .send({
      from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
      gas: 470000000
    })
    .on("transactionHash", txHash => {
      console.log(txHash);
    })
    .on("receipt", zvReceipt => {
      // ------ Burn Verifier ------//
      bvContract
        .deploy({
          data: bvBytecode
        })
        .send({
          from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
          gas: 470000000
        })
        .on("transactionHash", txHash => {
          console.log(txHash);
        })
        .on("receipt", bvReceipt => {
          // ------ ERC20 Contract ------//
          erc20Contract
            .deploy({
              data: erc20Bytecode
            })
            .send({
              from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
              gas: 470000000
            })
            .on("transactionHash", txHash => {
              console.log(txHash);
            })
            .on("receipt", erc20Receipt => {
              // ------ ZSC Contract ------//
              zscContract
                .deploy({
                  data: zscBytecode,
                  arguments: [
                    erc20Receipt.contractAddress,
                    zvReceipt.contractAddress,
                    bvReceipt.contractAddress,
                    3000
                  ]
                })
                .send({
                  from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
                  gas: 470000000
                })
                .on("transactionHash", txHash => {
                  console.log(txHash);
                })
                .on("receipt", zscReceipt => {
                  console.log("zvReceipt", zvReceipt);
                  console.log("bvReceipt", bvReceipt);
                  console.log("erc20Receipt", erc20Receipt);
                  console.log("zscReceipt", zscReceipt);
                  const deployedZSC = new web3Socket.eth.Contract(
                    zscAbi,
                    "0x6585c8466ecD527Dda9E09eBC1390ECab0844F2C"
                  );
                  const az = new Client(deployedZSC);

                  console.log(az.accounts.showAccounts());
                });
            });
        });
    });
})();
