const Web3 = require("web3");
const InnerProductVerifier = require("../contract-artifacts/artifacts/InnerProductVerifier.json");
const ZetherVerifier = require("../contract-artifacts/artifacts/ZetherVerifier.json");
const BurnVerifier = require("../contract-artifacts/artifacts/BurnVerifier.json");
const CashToken = require("../contract-artifacts/artifacts/CashToken.json");
const ZSC = require("../contract-artifacts/artifacts/ZSC.json");

class Deployer {
    constructor(accounts) {
        const web3 = new Web3(new Web3.providers.HttpProvider("http://localhost:22000"))
        web3.transactionConfirmationBlocks = 1;

        this.deployInnerProductVerifier = () => {
            const contract = new web3.eth.Contract(InnerProductVerifier.abi);
            return new Promise((resolve, reject) => {
                contract.deploy({ data: InnerProductVerifier.bytecode }).send({ from: accounts[0], gas: 4700000 })
                    .on("receipt", (receipt) => {
                        console.log("Inner product verifier mined (address = \"" + receipt.contractAddress + "\").");
                        resolve(receipt);
                    })
                    .on("error", (error) => {
                        reject(error);
                    });
            });
        }

        this.deployZetherVerifier = (ip) => {
            const contract = new web3.eth.Contract(ZetherVerifier.abi);
            return new Promise((resolve, reject) => {
                contract.deploy({ data: ZetherVerifier.bytecode, arguments: [ip] }).send({ from: accounts[0], gas: 8000000 })
                    .on("receipt", (receipt) => {
                        console.log("Zether verifier mined (address = \"" + receipt.contractAddress + "\").");
                        resolve(receipt);
                    })
                    .on("error", (error) => {
                        reject(error);
                    });
            });
        };

        this.deployBurnVerifier = (ip) => {
            const contract = new web3.eth.Contract(BurnVerifier.abi);
            return new Promise((resolve, reject) => {
                contract.deploy({ data: BurnVerifier.bytecode, arguments: [ip] }).send({ from: accounts[0], gas: 4700000 })
                    .on("receipt", (receipt) => {
                        console.log("Burn verifier mined (address = \"" + receipt.contractAddress + "\").");
                        resolve(receipt);
                    })
                    .on("error", (error) => {
                        reject(error);
                    });
            });
        };

        this.deployCashToken = () => {
            const contract = new web3.eth.Contract(CashToken.abi);
            return new Promise((resolve, reject) => {
                contract.deploy({ data: CashToken.bytecode }).send({ from: accounts[0], gas: 4700000 })
                    .on("receipt", (receipt) => {
                        console.log("Cash token contact mined (address = \"" + receipt.contractAddress + "\").");
                        resolve(receipt);
                    })
                    .on("error", (error) => {
                        reject(error);
                    });
            });
        };

        this.mintCashToken = (cash, amount) => {
            const contract = new web3.eth.Contract(CashToken.abi, cash);
            return new Promise((resolve, reject) => {
                contract.methods.mint(accounts[0], amount).send({ from: accounts[0], gas: 4700000 })
                    .on("receipt", (receipt) => {
                        contract.methods.balanceOf(accounts[0]).call()
                            .then((result) => {
                                console.log("ERC20 funds minted (balance = " + result + ").");
                                resolve(receipt);
                            });
                    })
                    .on("error", (error) => {
                        reject(error);
                    });
            });
        };

        this.approveCashToken = (cash, zsc, amount) => {
            const contract = new web3.eth.Contract(CashToken.abi, cash);
            return new Promise((resolve, reject) => {
                contract.methods.approve(zsc, amount).send({ from: accounts[0], gas: 4700000 })
                    .on("receipt", (receipt) => {
                        contract.methods.allowance(accounts[0], zsc).call()
                            .then((result) => {
                                console.log("ERC funds approved for transfer to ZSC (allowance = " + result + ").");
                                resolve(receipt);
                            });
                    })
                    .on("error", (error) => {
                        reject(error);
                    });
            });
        };

        this.deployZSC = (cash, zether, burn, epochLength) => {
            const contract = new web3.eth.Contract(ZSC.abi);
            return new Promise((resolve, reject) => {
                contract.deploy({ data: ZSC.bytecode, arguments: [cash, zether, burn, epochLength] }).send({ from: accounts[0], gas: 4700000 })
                    .on("receipt", (receipt) => {
                        console.log("ZSC main contract deployed (address = \"" + receipt.contractAddress + "\").");
                        resolve(receipt);
                    })
                    .on("error", (error) => {
                        reject(error);
                    });
            });
        };
    }
}

module.exports = Deployer;