const Web3 = require("web3");
const ZV = require("../contract-artifacts/artifacts/ZetherVerifier.json");
const BV = require("../contract-artifacts/artifacts/BurnVerifier.json");
const ERC20 = require("../contract-artifacts/artifacts/CashToken.json");
const ZSC = require("../contract-artifacts/artifacts/ZSC.json");

const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:22000"));
web3.transactionConfirmationBlocks = 1;

module.exports = {
  DeployZV: () => {
    const abi = ZV.abi;
    const bytecode = ZV.bytecode;
    const contract = new web3.eth.Contract(abi);
    return new Promise((resolve, reject) => {
      contract
      .deploy({
        data: bytecode
      })
      .send({
        from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
        gas: 470000000
      })
      .on("error", err => {
          reject(err);
      })
      .on("transactionHash", txHash => {
        console.log(txHash);
      })
      .on("receipt", receipt => {
          resolve(receipt)
      })
    })
  },
  DeployBV: () => {
    const abi = BV.abi;
    const bytecode = BV.bytecode;
    const contract = new web3.eth.Contract(abi);
    return new Promise((resolve, reject) => {
      contract
      .deploy({
        data: bytecode
      })
      .send({
        from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
        gas: 470000000
      })
      .on("error", err => {
          reject(err);
      })
      .on("transactionHash", txHash => {
        console.log(txHash);
      })
      .on("receipt", receipt => {
          resolve(receipt)
      })
    })
  },
  DeployERC20: () => {
    const abi = ERC20.abi;
    const bytecode = ERC20.bytecode;
    const contract = new web3.eth.Contract(abi);
    return new Promise((resolve, reject) => {
      contract
      .deploy({
        data: bytecode
      })
      .send({
        from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
        gas: 470000000
      })
      .on("error", err => {
          reject(err);
      })
      .on("transactionHash", txHash => {
        console.log(txHash);
      })
      .on("receipt", receipt => {
        resolve(receipt);
      })
    })
  },
  MintERC20: contractAddress => {
    const abi = ERC20.abi;
    const ercContract = web3.eth.Contract(abi, contractAddress);
    return new Promise((resolve, reject) => {
      ercContract.methods.mint("0xed9d02e382b34818e88B88a309c7fe71E65f419d", 1000000000000)
      .send({
        from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
        gas: 470000000
      })
      .on("error", err => {
          reject(err);
      })
      .on("transactionHash", txHash => {
        console.log(txHash);
      })
      .on("receipt", receipt => {
        ercContract.methods.balanceOf("0xed9d02e382b34818e88B88a309c7fe71E65f419d").call().then(balance=>{
          console.log("balance", balance);
          resolve(receipt)
        });
      });
    });
  },
  ApproveERC20: (contractAddress, zscAddress) => {
    const abi = ERC20.abi;
    const ercContract = web3.eth.Contract(abi, contractAddress);
    return new Promise((resolve, reject) => {
      ercContract.methods.approve(zscAddress, 1000000000)
      .send({
        from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
        gas: 470000000
      })
      .on("error", err => {
          reject(err);
      })
      .on("transactionHash", txHash => {
        console.log(txHash);
      })
      .on("receipt", receipt => {
        ercContract.methods.allowance("0xed9d02e382b34818e88B88a309c7fe71E65f419d", zscAddress).call().then(allowance=>{
          console.log("allowance", allowance);
          resolve(receipt)
        });
      });
    });
  },
  DeployZSC: (zetherAddress, burnAddress, erc20Address) => {
    const abi = ZSC.abi;
    const bytecode = ZSC.bytecode;
    const contract = new web3.eth.Contract(abi);
    return new Promise((resolve, reject) => {
      contract
      .deploy({
        data: bytecode,
        arguments: [
          erc20Address,
          zetherAddress,
          burnAddress,
          3000
        ]
      })
      .send({
        from: "0xed9d02e382b34818e88b88a309c7fe71e65f419d",
        gas: 470000000
      })
      .on("error", err => {
          reject(err);
      })
      .on("transactionHash", txHash => {
        console.log(txHash);
      })
      .on("receipt", receipt => {
          resolve(receipt)
      })
    })
  }
}