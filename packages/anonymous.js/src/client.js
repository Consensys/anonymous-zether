const crypto = require('crypto');
const BN = require('bn.js');

const utils = require('./utils/utils.js');
const { ElGamal } = require('./utils/algebra.js');
const Service = require('./utils/service.js');
const bn128 = require('./utils/bn128.js');

const sleep = (wait) => new Promise((resolve) => { setTimeout(resolve, wait); });

class Client {
    constructor(web3, zsc, home) {
        if (web3 === undefined)
            throw "Constructor's first argument should be an initialized Web3 object.";
        if (zsc === undefined)
            throw "Constructor's second argument should be a deployed ZSC contract object.";
        if (home === undefined)
            throw "Constructor's third argument should be the address of an unlocked Ethereum account.";

        web3.transactionConfirmationBlocks = 1;
        const that = this;

        const transfers = new Set();
        let epochLength = undefined;
        let fee = undefined;

        const getEpoch = (timestamp) => {
            return Math.floor((timestamp === undefined ? (new Date).getTime() / 1000 : timestamp) / epochLength);
        };

        const away = () => { // returns ms away from next epoch change
            const current = (new Date).getTime();
            return Math.ceil(current / (epochLength * 1000)) * (epochLength * 1000) - current;
        };

        const estimate = (size, contract) => {
            // this expression is meant to be a relatively close upper bound of the time that proving + a few verifications will take, as a function of anonset size
            // this function should hopefully give you good epoch lengths also for 8, 16, 32, etc... if you have very heavy traffic, may need to bump it up (many verifications)
            // i calibrated this on _my machine_. if you are getting transfer failures, you might need to bump up the constants, recalibrate yourself, etc.
            return Math.ceil(size * Math.log(size) / Math.log(2) * 20 + 5200) + (contract ? 20 : 0);
            // the 20-millisecond buffer is designed to give the callback time to fire (see below).
        };

        zsc.events.TransferOccurred({}) // i guess this will just filter for "from here on out."
            // an interesting prospect is whether balance recovery could be eliminated by looking at past events.
            .on('data', (event) => {
                if (transfers.has(event.transactionHash)) {
                    transfers.delete(event.transactionHash);
                    return;
                }
                const account = this.account;
                if (event.returnValues['parties'] === null) return; // truffle is sometimes emitting spurious empty events??? have to avoid this case manually.
                event.returnValues['parties'].forEach((party, i) => {
                    if (account.keypair['y'].eq(bn128.deserialize(party))) {
                        const blockNumber = event.blockNumber;
                        web3.eth.getBlock(blockNumber).then((block) => {
                            account._state = account._simulate(block.timestamp);
                            web3.eth.getTransaction(event.transactionHash).then((transaction) => {
                                let inputs;
                                zsc._jsonInterface.forEach((element) => {
                                    if (element['name'] === "transfer")
                                        inputs = element['inputs'];
                                });
                                const parameters = web3.eth.abi.decodeParameters(inputs, "0x" + transaction.input.slice(10));
                                const value = utils.readBalance(parameters['C'][i], parameters['D'], account.keypair['x']);
                                if (value > 0) {
                                    account._state.pending += value;
                                    console.log("Transfer of " + value + " received! Balance now " + (account._state.available + account._state.pending) + ".");
                                }
                            });
                        });
                    }
                });
                if (account.keypair['y'].eq(bn128.deserialize(event.returnValues['beneficiary']))) {
                    account._state.pending += fee;
                    console.log("Fee of " + fee + " received! Balance now " + (account._state.available + account._state.pending) + ".");
                }
            })
            .on('error', (error) => {
                console.log(error); // when will this be called / fired...?! confusing. also, test this.
            });

        this.account = new function() {
            this.keypair = undefined;
            this._state = {
                available: 0,
                pending: 0,
                nonceUsed: 0,
                lastRollOver: 0
            };

            this._simulate = (timestamp) => {
                const updated = {};
                updated.available = this._state.available;
                updated.pending = this._state.pending;
                updated.nonceUsed = this._state.nonceUsed;
                updated.lastRollOver = getEpoch(timestamp);
                if (this._state.lastRollOver < updated.lastRollOver) {
                    updated.available += updated.pending;
                    updated.pending = 0;
                    updated.nonceUsed = false;
                }
                return updated;
            };

            this.balance = () => this._state.available + this._state.pending;
            this.public = () => bn128.serialize(this.keypair['y']);
            this.secret = () => "0x" + this.keypair['x'].toString(16, 64);
        };

        this.friends = new function() {
            const friends = {};
            this.add = (name, pubkey) => {
                // todo: checks that these are properly formed, of the right types, etc...
                friends[name] = bn128.deserialize(pubkey);
                return "Friend added.";
            };

            this.show = () => friends;
            this.remove = (name) => {
                if (!(name in friends))
                    throw "Friend " + name + " not found in directory!";
                delete friends[name];
                return "Friend deleted.";
            };
        };

        this.register = (secret) => {
            return Promise.all([zsc.methods.epochLength().call(), zsc.methods.fee().call()]).then((result) => {
                epochLength = parseInt(result[0]);
                fee = parseInt(result[1]);
                return new Promise((resolve, reject) => {
                    if (secret === undefined) {
                        const keypair = utils.createAccount();
                        const [c, s] = utils.sign(zsc._address, keypair);
                        zsc.methods.register(bn128.serialize(keypair['y']), c, s).send({ 'from': home, 'gas': 6721975 })
                            .on('transactionHash', (hash) => {
                                console.log("Registration submitted (txHash = \"" + hash + "\").");
                            })
                            .on('receipt', (receipt) => {
                                that.account.keypair = keypair;
                                console.log("Registration successful.");
                                resolve();
                            })
                            .on('error', (error) => {
                                console.log("Registration failed: " + error);
                                reject(error);
                            });
                    } else {
                        const x = new BN(secret.slice(2), 16).toRed(bn128.q);
                        that.account.keypair = { 'x': x, 'y': bn128.curve.g.mul(x) };
                        zsc.methods.simulateAccounts([bn128.serialize(this.account.keypair['y'])], getEpoch() + 1).call().then((result) => {
                            const simulated = result[0];
                            that.account._state.available = utils.readBalance(simulated[0], simulated[1], x);
                            console.log("Account recovered successfully.");
                            resolve(); // warning: won't register you. assuming you registered when you first created the account.
                        });
                    }
                });
            });
        };

        this.deposit = (value) => {
            if (this.account.keypair === undefined)
                throw "Client's account is not yet registered!";
            const account = this.account;
            console.log("Initiating deposit.");
            return new Promise((resolve, reject) => {
                zsc.methods.fund(bn128.serialize(account.keypair['y']), value).send({ 'from': home, 'gas': 6721975 })
                    .on('transactionHash', (hash) => {
                        console.log("Deposit submitted (txHash = \"" + hash + "\").");
                    })
                    .on('receipt', (receipt) => {
                        account._state = account._simulate(); // have to freshly call it
                        account._state.pending += value;
                        console.log("Deposit of " + value + " was successful. Balance now " + (account._state.available + account._state.pending) + ".");
                        resolve(receipt);
                    })
                    .on('error', (error) => {
                        console.log("Deposit failed: " + error);
                        reject(error);
                    });
            });
        };

        this.transfer = (name, value, decoys, beneficiary) => { // todo: make sure the beneficiary is registered.
            if (this.account.keypair === undefined)
                throw "Client's account is not yet registered!";
            decoys = decoys ? decoys : [];
            const account = this.account;
            const state = account._simulate();
            if (value + fee > state.available + state.pending)
                throw "Requested transfer amount of " + value + " (plus fee of " + fee + ") exceeds account balance of " + (state.available + state.pending) + ".";
            const wait = away();
            const seconds = Math.ceil(wait / 1000);
            const plural = seconds === 1 ? "" : "s";
            if (value > state.available) {
                console.log("Your transfer has been queued. Please wait " + seconds + " second" + plural + ", for the release of your funds...");
                return sleep(wait).then(() => this.transfer(name, value, decoys, beneficiary));
            }
            if (state.nonceUsed) {
                console.log("Your transfer has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...");
                return sleep(wait).then(() => this.transfer(name, value, decoys, beneficiary));
            }
            const size = 2 + decoys.length;
            const estimated = estimate(size, false); // see notes above
            if (estimated > epochLength * 1000)
                throw "The anonset size (" + size + ") you've requested might take longer than the epoch length (" + epochLength + " seconds) to prove. Consider re-deploying, with an epoch length at least " + Math.ceil(estimate(size, true) / 1000) + " seconds.";
            if (estimated > wait) {
                console.log(wait < 3100 ? "Initiating transfer." : "Your transfer has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...");
                return sleep(wait).then(() => this.transfer(name, value, decoys, beneficiary));
            }
            if (size & (size - 1)) {
                let previous = 1;
                let next = 2;
                while (next < size) {
                    previous *= 2;
                    next *= 2;
                }
                throw "Anonset's size (including you and the recipient) must be a power of two. Add " + (next - size) + " or remove " + (size - previous) + ".";
            }
            const friends = this.friends.show();
            if (!(name in friends))
                throw "Name \"" + name + "\" hasn't been friended yet!";
            if (account.keypair['y'].eq(friends[name]))
                throw "Sending to yourself is currently unsupported (and useless!)."
            const y = [account.keypair['y'], friends[name]]; // not yet shuffled
            decoys.forEach((decoy) => {
                if (!(decoy in friends))
                    throw "Decoy \"" + decoy + "\" is unknown in friends directory!";
                y.push(friends[decoy]);
            });
            if (beneficiary !== undefined && !(beneficiary in friends))
                throw "Beneficiary \"" + beneficiary + "\" is not known!";
            const index = [];
            let m = y.length;
            while (m !== 0) { // https://bost.ocks.org/mike/shuffle/
                const i = crypto.randomBytes(1).readUInt8() % m--; // warning: N should be <= 256. also modulo bias.
                const temp = y[i];
                y[i] = y[m];
                y[m] = temp;
                if (account.keypair['y'].eq(temp)) index[0] = m;
                else if (friends[name].eq(temp)) index[1] = m;
            } // shuffle the array of y's
            if (index[0] % 2 === index[1] % 2) {
                const temp = y[index[1]];
                y[index[1]] = y[index[1] + (index[1] % 2 === 0 ? 1 : -1)];
                y[index[1] + (index[1] % 2 === 0 ? 1 : -1)] = temp;
                index[1] = index[1] + (index[1] % 2 === 0 ? 1 : -1);
            } // make sure you and your friend have opposite parity
            return new Promise((resolve, reject) => {
                zsc.methods.simulateAccounts(y.map(bn128.serialize), getEpoch()).call().then((result) => {
                    const deserialized = result.map((account) => ElGamal.deserialize(account));
                    if (deserialized.some((account) => account.zero()))
                        return reject(new Error("Please make sure all parties (including decoys) are registered.")); // todo: better error message, i.e., which friend?
                    const r = bn128.randomScalar();
                    const D = bn128.curve.g.mul(r);
                    const C = y.map((party, i) => {
                        const left = ElGamal.base['g'].mul(new BN(i === index[0] ? -value - fee : i === index[1] ? value : 0)).add(party.mul(r))
                        return new ElGamal(left, D)
                    });
                    const Cn = deserialized.map((account, i) => account.add(C[i]));
                    const proof = Service.proveTransfer(Cn, C, y, state.lastRollOver, account.keypair['x'], r, value, state.available - value - fee, index, fee);
                    const u = utils.u(state.lastRollOver, account.keypair['x']);
                    const throwaway = web3.eth.accounts.create();
                    const beneficiaryKey = beneficiary === undefined ? bn128.zero : friends[beneficiary];
                    const encoded = zsc.methods.transfer(C.map((ciphertext) => bn128.serialize(ciphertext.left())), bn128.serialize(D), y.map(bn128.serialize), bn128.serialize(u), proof.serialize(), bn128.serialize(beneficiaryKey)).encodeABI();
                    const tx = { 'to': zsc._address, 'data': encoded, 'gas': 7721975, 'nonce': 0 };
                    web3.eth.accounts.signTransaction(tx, throwaway.privateKey).then((signed) => {
                        web3.eth.sendSignedTransaction(signed.rawTransaction)
                            .on('transactionHash', (hash) => {
                                transfers.add(hash);
                                console.log("Transfer submitted (txHash = \"" + hash + "\").");
                            })
                            .on('receipt', (receipt) => {
                                account._state = account._simulate(); // have to freshly call it
                                account._state.nonceUsed = true;
                                account._state.pending -= value + fee;
                                console.log("Transfer of " + value + " (with fee of " + fee + ") was successful. Balance now " + (account._state.available + account._state.pending) + ".");
                                resolve(receipt);
                            })
                            .on('error', (error) => {
                                console.log("Transfer failed: " + error);
                                reject(error);
                            });
                    });
                });
            });
        };

        this.withdraw = (value) => {
            if (this.account.keypair === undefined)
                throw "Client's account is not yet registered!";
            const account = this.account;
            const state = account._simulate();
            if (value > state.available + state.pending)
                throw "Requested withdrawal amount of " + value + " exceeds account balance of " + (state.available + state.pending) + ".";
            const wait = away();
            const seconds = Math.ceil(wait / 1000);
            const plural = seconds === 1 ? "" : "s";
            if (value > state.available) {
                console.log("Your withdrawal has been queued. Please wait " + seconds + " second" + plural + ", for the release of your funds...");
                return sleep(wait).then(() => this.withdraw(value));
            }
            if (state.nonceUsed) {
                console.log("Your withdrawal has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...");
                return sleep(wait).then(() => this.withdraw(value));
            }
            if (3100 > wait) { // determined empirically. IBFT, block time 1
                console.log("Initiating withdrawal.");
                return sleep(wait).then(() => this.withdraw(value));
            }
            return new Promise((resolve, reject) => {
                zsc.methods.simulateAccounts([bn128.serialize(account.keypair['y'])], getEpoch()).call()
                    .then((result) => {
                        const deserialized = ElGamal.deserialize(result[0]);
                        const C = deserialized.plus(new BN(-value));
                        const proof = Service.proveBurn(C, account.keypair['y'], state.lastRollOver, home, account.keypair['x'], state.available - value);
                        const u = utils.u(state.lastRollOver, account.keypair['x']);
                        zsc.methods.burn(bn128.serialize(account.keypair['y']), value, bn128.serialize(u), proof.serialize()).send({ 'from': home, 'gas': 6721975 })
                            .on('transactionHash', (hash) => {
                                console.log("Withdrawal submitted (txHash = \"" + hash + "\").");
                            })
                            .on('receipt', (receipt) => {
                                account._state = account._simulate(); // have to freshly call it
                                account._state.nonceUsed = true;
                                account._state.pending -= value;
                                console.log("Withdrawal of " + value + " was successful. Balance now " + (account._state.available + account._state.pending) + ".");
                                resolve(receipt);
                            }).on('error', (error) => {
                                console.log("Withdrawal failed: " + error);
                                reject(error);
                            });
                    });
            });
        };
    }
}

module.exports = Client;