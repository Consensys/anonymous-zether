const BN = require('BN.js');

const utils = require('./utils/utils.js');
const Service = require('./utils/service.js');
const bn128 = require('./utils/bn128.js');

var sleep = (wait) => new Promise((resolve) => setTimeout(resolve, wait));

class Client {
    constructor(zsc, home, web3) {
        if (zsc === undefined) {
            throw "Please provide an argument pointing to a deployed ZSC contract!";
        }
        if (home === undefined) {
            throw "Please specify an unlocked ethereum account.";
        }
        var that = this;
        var match = (address, candidate) => {
            return address[0] == candidate[0] && address[1] == candidate[1];
        };

        var service = new Service();

        this._transfers = new Set();
        zsc.events.TransferOccurred({}) // i guess this will just filter for "from here on out."
            // an interesting prospect is whether balance recovery could be eliminated by looking at past events.
            .on('data', (event) => {
                if (that._transfers.has(event.transactionHash)) {
                    that._transfers.delete(event.transactionHash);
                    return;
                }
                var account = that.account;
                event.returnValues['parties'].forEach((party, i) => {
                    if (match(account.keypair['y'], party)) {
                        var blockNumber = event.blockNumber;
                        web3.eth.getBlock(blockNumber).then((block) => {
                            account._state = account._simulateBalances(block.timestamp / 1000000); // divide by 1000000 for quorum...?
                            web3.eth.getTransaction(event.transactionHash).then((transaction) => {
                                var inputs = zsc.jsonInterface.abi.methods.transfer.abiItem.inputs;
                                var parameters = web3.eth.abi.decodeParameters(inputs, "0x" + transaction.input.slice(10));
                                var value = utils.readBalance(parameters['L'][i], parameters['R'], account.keypair['x']);
                                if (value > 0) {
                                    account._state.pending += value;
                                    console.log("Transfer of " + value + " received! Balance now " + (account._state.available + account._state.pending) + ".");
                                }
                            });
                        });
                    }
                });
            })
            .on('error', (error) => {
                console.log(error); // when will this be called / fired...?! confusing. also, test this.
            });

        this._epochLength = undefined;
        this._getEpoch = (timestamp) => {
            return Math.floor((timestamp === undefined ? (new Date).getTime() : timestamp) / this._epochLength);
        };
        this._away = () => {
            var current = (new Date).getTime();
            return Math.ceil(current / this._epochLength) * this._epochLength - current;
        };

        this.account = new function() {
            this.keypair = undefined;
            this._state = {
                available: 0,
                pending: 0,
                nonceUsed: 0,
                lastRollOver: 0
            };

            this._simulateBalances = (timestamp) => {
                var updated = {};
                updated.available = this._state.available;
                updated.pending = this._state.pending;
                updated.nonceUsed = this._state.nonceUsed;
                updated.lastRollOver = that._getEpoch(timestamp);
                if (this._state.lastRollOver < updated.lastRollOver) {
                    updated.available += updated.pending;
                    updated.pending = 0;
                    updated.nonceUsed = false;
                }
                return updated;
            };

            this.balance = () => {
                return this.account._state.available + this.account._state.pending;
            };

            this.secret = () => {
                return bn128.bytes(x);
            };

            this.initialize = async (secret) => {
                return new Promise((resolve, reject) => {
                    zsc.methods.epochLength().call()
                        .then((result) => {
                            that._epochLength = result;
                            if (secret === undefined) {
                                var keypair = utils.createAccount();
                                that.account.keypair = keypair;
                                zsc.methods.register(that.account.keypair['y']).send({ from: home, gas: 5470000 })
                                    .on('transactionHash', (hash) => {
                                        console.log("Registration submitted (txHash = \"" + hash + "\").");
                                    })
                                    .on('receipt', (receipt) => {
                                        console.log("Registration successful.");
                                        resolve(receipt);
                                    })
                                    .on('error', (error) => {
                                        console.log("Registration failed! Create a new `client` (do not use this one).");
                                        reject(error);
                                    });
                            } else {
                                var x = new BN(secret, 16).toRed(bn128.q);
                                that.account.keypair = { 'x': x, 'y': utils.determinePublicKey(x) };
                                zsc.methods.simulateAccounts([that.account.keypair['y']], that._getEpoch() + 1).call()
                                    .then((result) => {
                                        var simulated = result[0];
                                        that.account._state.available = utils.readBalance(simulated[0], simulated[1], that.account.keypair['x']);
                                        console.log("Account recovered successfully.");
                                        resolve(); // inconsistent that the above is resolved with a receipt and this not, but...
                                    });
                            }
                        });
                })
            };
        };

        this.friends = new function() {
            var friends = {};
            this.addFriend = (name, pubkey) => {
                // todo: checks that these are properly formed, of the right types, etc...
                friends[name] = pubkey;
                return "Friend added.";
            };

            this.showFriends = () => {
                return friends;
            };

            this.removeFriend = (name) => {
                if (!(name in friends)) {
                    throw "Friend " + name + " not found in directory!";
                }
                delete friends[name];
                return "Friend deleted.";
            };
        };

        this.deposit = (value) => {
            var account = this.account;
            console.log("Initiating deposit.");
            return new Promise((resolve, reject) => {
                zsc.methods.fund(account.keypair['y'], value).send({ from: home, gas: 5470000 })
                    .on('transactionHash', (hash) => {
                        console.log("Deposit submitted (txHash = \"" + hash + "\").");
                    })
                    .on('receipt', (receipt) => {
                        account._state = account._simulateBalances(); // have to freshly call it
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

        var estimate = (size, contract) => {
            // this expression is meant to be a relatively close upper bound of the time that proving + a few verifications will take, as a function of anonset size
            // this function should hopefully give you good epoch lengths also for 8, 16, 32, etc... if you have very heavy traffic, may need to bump it up (many verifications)
            // i calibrated this on _my machine_. if you are getting transfer failures, you might need to bump up the constants, recalibrate yourself, etc.
            return Math.ceil(size * Math.log(size) / Math.log(2) * 25 + 2000) + (contract ? 20 : 0);
            // the 20-millisecond buffer is designed to give the callback time to fire (see below).
        };

        this.transfer = (name, value, decoys) => {
            decoys = decoys ? decoys : [];
            var account = this.account;
            var state = account._simulateBalances();
            if (value > state.available + state.pending)
                throw "Requested transfer amount of " + value + " exceeds account balance of " + (state.available + state.pending) + ".";
            var wait = this._away();
            var seconds = Math.ceil(wait / 1000);
            var plural = seconds == 1 ? "" : "s";
            if (value > state.available) {
                console.log("Your transfer has been queued. Please wait " + seconds + " second" + plural + ", for the release of your funds...");
                return sleep(wait).then(() => this.transfer(name, value, decoys));
            }
            if (state.nonceUsed) {
                console.log("Your transfer has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...");
                return sleep(wait).then(() => this.transfer(name, value, decoys));
            }
            var size = 2 + decoys.length;
            var estimated = estimate(size, false); // see notes above
            if (estimated > this._epochLength)
                throw "The size (" + size + ") you've requested might take longer than the epoch length " + this._epochLength + " ms to prove. Consider re-deploying, with an epoch at least " + estimate(size, true) + " ms.";
            if (estimated > wait) {
                console.log(wait < 2000 ? "Initiating transfer." : "Your transfer has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...");
                return sleep(wait).then(() => this.transfer(name, value, decoys));
            }
            if (size & (size - 1)) {
                var previous = 1;
                var next = 2;
                while (next < size) {
                    previous *= 2;
                    next *= 2;
                }
                throw "Anonset's size (including you and the recipient) must be a power of two. Add " + (next - size) + " or remove " + (size - previous) + ".";
            }
            var friends = that.friends.showFriends();
            if (!(name in friends))
                throw "Name \"" + name + "\" hasn't been friended yet!";
            var y = [account.keypair['y']].concat([friends[name]]); // not yet shuffled
            decoys.forEach((decoy) => {
                if (!(decoy in friends)) {
                    throw "Decoy \"" + decoy + "\" is unknown in friends directory!";
                }
                y.push(friends[decoy]);
            });
            var index = [];
            var m = y.length;
            while (m != 0) { // https://bost.ocks.org/mike/shuffle/
                var i = Math.floor(Math.random() * m--);
                var temp = y[i];
                y[i] = y[m];
                y[m] = temp;
                if (match(temp, account.keypair['y']))
                    index[0] = m;
                else if (match(temp, friends[name]))
                    index[1] = m;
            } // shuffle the array of y's
            if (index[0] % 2 == index[1] % 2) {
                var temp = y[index[1]];
                y[index[1]] = y[index[1] + (index[1] % 2 == 0 ? 1 : -1)];
                y[index[1] + (index[1] % 2 == 0 ? 1 : -1)] = temp;
                index[1] = index[1] + (index[1] % 2 == 0 ? 1 : -1);
            } // make sure you and your friend have opposite parity
            return new Promise((resolve, reject) => {
                zsc.methods.simulateAccounts(y, this._getEpoch()).call()
                    .then((result) => {
                        var r = bn128.randomScalar();
                        var L = y.map((party, i) => bn128.curve.g.mul(i == index[0] ? new BN(-value) : i == index[1] ? new BN(value) : new BN(0)).add(bn128.curve.point(party[0].slice(2), party[1].slice(2)).mul(r)));
                        var R = bn128.curve.g.mul(r);
                        var CLn = result.map((simulated, i) => bn128.serialize(bn128.curve.point(simulated[0][0].slice(2), simulated[0][1].slice(2)).add(L[i])));
                        var CRn = result.map((simulated) => bn128.serialize(bn128.curve.point(simulated[1][0].slice(2), simulated[1][1].slice(2)).add(R)));
                        var proof = service.proveTransfer(CLn, CRn, L.map(bn128.serialize), bn128.serialize(R), y, state.lastRollOver, account.keypair['x'], r, value, state.available - value, index);
                        var u = bn128.serialize(utils.u(state.lastRollOver, account.keypair['x']));
                        var throwaway = web3.eth.accounts.create();
                        var encoded = zsc.methods.transfer(L, R, y, u, proof).encodeABI();
                        var tx = { 'to': zsc.address, 'data': encoded, 'gas': 2000000000, 'nonce': 0 };
                        web3.eth.accounts.signTransaction(tx, throwaway.privateKey).then((signed) => {
                            web3.eth.sendSignedTransaction(signed.rawTransaction)
                                .on('transactionHash', (hash) => {
                                    that._transfers.add(hash);
                                    console.log("Transfer submitted (txHash = \"" + hash + "\").");
                                })
                                .on('receipt', (receipt) => {
                                    account._state = account._simulateBalances(); // have to freshly call it
                                    account._state.nonceUsed = true;
                                    account._state.pending -= value;
                                    console.log("Transfer of " + value + " was successful. Balance now " + (account._state.available + account._state.pending) + ".");
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
            var account = this.account;
            var state = account._simulateBalances();
            if (value > state.available + state.pending)
                throw "Requested withdrawal amount of " + value + " exceeds account balance of " + (state.available + state.pending) + ".";
            var wait = this._away();
            var seconds = Math.ceil(wait / 1000);
            var plural = seconds == 1 ? "" : "s";
            if (value > state.available) {
                console.log("Your withdrawal has been queued. Please wait " + seconds + " second" + plural + ", for the release of your funds...");
                return sleep(wait).then(() => this.withdraw(value));
            }
            if (state.nonceUsed) {
                console.log("Your withdrawal has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...");
                return sleep(wait).then(() => this.withdraw(value));
            }
            if (2000 > wait) { // withdrawals will take <= 2 seconds (actually, more like 1)...
                console.log("Initiating withdrawal.");
                return sleep(wait).then(() => this.withdraw(value));
            }
            return new Promise((resolve, reject) => {
                zsc.methods.simulateAccounts([account.keypair['y']], this._getEpoch()).call()
                    .then((result) => {
                        var simulated = result[0];
                        var CLn = bn128.serialize(bn128.unserialize(simulated[0]).add(bn128.curve.g.mul(new BN(-value))));
                        var CRn = simulated[1];
                        var proof = service.proveBurn(CLn, CRn, account.keypair['y'], value, state.lastRollOver, account.keypair['x'], state.available - value);
                        var u = bn128.serialize(utils.u(state.lastRollOver, account.keypair['x']));
                        zsc.methods.burn(account.keypair['y'], value, u, proof).send({ from: home, gas: 547000000 })
                            .on('transactionHash', (hash) => {
                                console.log("Withdrawal submitted (txHash = \"" + hash + "\").");
                            })
                            .on('receipt', (receipt) => {
                                account._state = account._simulateBalances(); // have to freshly call it
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