const maintenance = require('./utils/maintenance.js');
const service = require('./utils/service.js');

function client(zsc) { // todo: how to ascertain the address(es) that the user wants to register against?
    if (zsc === undefined) {
        throw "Please provide an argument pointing to a deployed ZSC contract!";
    }
    var that = this;

    var home = "0xed9d02e382b34818e88b88a309c7fe71e65f419d";

    zsc.events.TransferOccurred({}, (error, event) => {
        var accounts = that.accounts.showAccounts();
        event.returnValues['parties'].forEach((party, i) => {
            accounts.forEach((account, j) => { // warning: slow?
                if (account['y'][0] == party[0] && account['y'][1] == party[1]) {
                    var blockNumber = event.blockNumber;
                    web3.eth.getBlock(blockNumber).then((block) => {
                        account._state = account._simulateBalances(block.timestamp / 1000000); // divide by 1000000 for quorum...?
                        var pending = account._state.pending;

                        web3.eth.getTransaction(event.transactionHash).then((transaction) => {
                            var inputs = zsc.jsonInterface.abi.methods.transfer.abiItem.inputs;
                            var parameters = web3.eth.abi.decodeParameters(inputs, "0x" + transaction.input.slice(10));
                            var value = maintenance.readBalance([parameters['L'][i], parameters['R']], account['x'])
                            if (value) {
                                account._state.pending += value;
                                console.log("Transfer of " + value + " received! Balance of account " + j + " is " + (that._state.available + that._state.pending) + ".");
                            }
                        })
                    });
                }
            });
        });
    })

    this._epochLength = undefined;
    zsc.methods.epochLength().call({}, (error, result) => {
        that._epochLength = result;
    }); // how to prevent use until this thing has been properly populated?
    this._getEpoch = function(timestamp) { // timestamp is in ms; so is epochLength.
        return Math.floor((timestamp === undefined ? (new Date).getTime() : timestamp) / this._epochLength);
    }

    this.accounts = new function() { // strange construction but works, revisit
        var register = (keypair, number) => {
            zsc.methods.register(keypair['y']).send({ from: home, gas: 5470000 })
                .on('transactionHash', (hash) => {
                    console.log("Initiating registration (txHash = \"" + hash + "\").");
                })
                .on('receipt', (receipt) => {
                    if (receipt.status) {
                        console.log("Registration of account " + number + " successful.");
                    } else {
                        console.log("Registration of account " + number + " failed! Do not use this account.");
                    }
                });
        }

        function account() {
            this.keypair = undefined;
            this._state = new function() { // don't touch this...
                this.available = 0;
                this.pending = 0;
                this.nonceUsed = 0;
                this.lastRollOver = 0;
            }
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
                return updated
            }
        }

        var accounts = [];
        this.addAccount = async (keypair) => { // a dict of the form { 'x': x, 'y': y } plus state stuff.
            // assuming that it is actually a proper keypair.
            if (keypair === undefined) {
                throw "Please specify the keypair of the account you'd like to add.";
            }
            var temp = new account();
            temp.keypair = keypair;
            var number = accounts.push(temp);
            await register(keypair, number);
            return "Account " + number + " added.";
        }
        this.newAccount = async () => {
            var keypair = maintenance.createAccount();
            var temp = new account();
            temp.keypair = keypair;
            var number = accounts.push(temp);
            await register(keypair, number);
            return "Account " + number + " generated."; // won't print it out for now.
        }
        this.showAccounts = () => {
            return accounts;
        }
    }

    this.friends = new function() {
        var friends = {};
        this.addFriend = (name, pubkey) => {
            // todo: checks that these are properly formed, of the right types, etc...
            friends[name] = pubkey;
            return "Friend added.";
        }
        this.showFriends = () => {
            return friends;
        }
        this.removeFriend = (name) => {
            if (!(name in friends)) {
                throw "Friend " + name + " not found in directory!";
            }
            delete friends[name];
            return "Friend deleted.";
        }
    }

    this.deposit = (value, number) => {
        number = number ? number : 1;
        var accounts = that.accounts.showAccounts();
        if (accounts.length < number) {
            throw "Account " + number + " not available! Please add more.";
        }
        var account = accounts[number - 1];
        zsc.methods.fund(account['y'], value).send({ from: home, gas: 5470000 })
            .on('transactionHash', (hash) => {
                console.log("Deposit submitted (txHash = \"" + hash + "\").");
            })
            .on('receipt', (receipt) => {
                if (receipt.status) {
                    account._state = account._simulateBalances(); // have to freshly call it
                    account._state.pending += value;
                    console.log("Deposit of " + value + " successful. Balance of account " + number + " is now " + (account._state.available + account._state.pending) + ".");
                } else {
                    console.log("Deposit failed (txHash = \"" + receipt.transactionHash + "\").");
                }
            });
        return "Initiating deposit.";
    }

    var estimate = (size, contract) => {
        // this expression is meant to be a relatively close upper bound of the time that proving + a few verifications will take, as a function of anonset size
        // this function should hopefully give you good epoch lengths also for 8, 16, 32, etc... if you have very heavy traffic, may need to bump it up (many verifications)
        // note that this estimation includes not just raw proving time but also "data gathering" time, which takes a while unfortunately (under the current setup)
        // batch requests are not available in this version of web3, and the performance is not good. hence the necessity of upgrading to a web3 1.0-based situation.
        // notes on this are below. if you do, be sure to update this function so that it reflects (an upper bound of) the actual rate of growth.
        return Math.ceil(size * Math.log(size) / Math.log(2) * 25 + 2000) + (contract ? 20 : 0);
        // the 20-millisecond buffer is designed to give the callback time to fire (see below).
    }

    var away = function() {
        current = (new Date).getTime();
        return Math.ceil(current / this._epochLength) * this._epochLength - current;
    }

    this.transfer = (name, value, decoys, number) => {
        number = number ? number : 1;
        var accounts = that.accounts.showAccounts();
        if (accounts.length < number) {
            throw "Account " + number + " not available! Please add more.";
        }
        var account = accounts[number - 1];

        var state = account._simulateBalances();
        if (value > state.available + state.pending)
            throw "Requested transfer amount of " + value + " exceeds account " + number + "'s balance of " + (state.available + state.pending) + ".";

        var wait = away();
        var seconds = Math.ceil(wait / 1000);
        var plural = seconds == 1 ? "" : "s";
        if (value > state.available) {
            var timer = setTimeout(() => {
                that.transfer(name, value, decoys, number);
            }, wait);
            return "Your transaction has been queued. Please wait " + seconds + " second" + plural + ", for the release of your funds...";
            // note: another option here would be to simply throw an error and abort.
            // the upside to doing that would be that the user might be willing to simply send a lower amount, and not have to wait.
            // the downside is of course if the user doesn't want that, then having to wait manually and then manually re-enter the transaction.
        }
        if (state.nonceUsed) {
            var timer = setTimeout(() => {
                that.transfer(name, value, number);
            }, wait);
            return "Your transaction has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...";
        }

        var size = 2 + (decoys ? decoys.length : 0);
        var estimated = estimate(size, false); // see notes above
        if (estimated > epochLength)
            throw "The size (" + size + ") you've requested might take longer than the epoch length " + epochLength + " ms to prove. Consider re-deploying, with an epoch at least " + estimate(size, true) + " ms.";
        if (estimated > wait) {
            var timer = setTimeout(() => {
                that.transfer(name, value, number);
            }, wait);
            return wait < 2000 ? "Initiating transfer." : "Your transaction has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...";
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
            if (this.mine(temp))
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

        // console.log("Gathering account state...")
        zsc.simulateAccounts(y, this._getEpoch()).call({}, (error, result) => {
            var CL = [];
            var CR = [];
            result.forEach((simulated) => {
                CL.push(simulated[0]);
                CR.push(simulated[1]);
            });

            // console.log("Generating proof...");  var r = bn128.randomGroupScalar()
            var r = bn128.randomScalar();
            var L = y.map((party, i) => bn128.canonicalRepresentation(bn128.curve.g.mul(i == index[0] ? new BN(-value) : i == index[1] ? new BN(value) : new BN(0)).add(bn128.curve.point(party[0].slice(2), party[1].slice(2)).mul(r))))
            var R = bn128.canonicalRepresentation(bn128.curve.g.mul(r));
            var u = maintenance.gEpoch(state.lastRollOver);
            service.proveTransfer(CL, CR, y, state.lastRollOver, account.keypair['x'], r, value, state.available - value, index, (proof) => {
                var throwaway = web3.eth.accounts.create(); // note: this will have to be signed locally!!! :(
                zsc.methods.transfer(L, R, y, u, proof).send({ from: throwaway.address, gas: 2000000000 })
                    .on('transactionHash', (hash) => {
                        console.log("Transfer submitted (txHash = \"" + hash + "\").");
                    })
                    .on('receipt', (receipt) => {
                        if (receipt.status) {
                            account._state = account._simulateBalances(); // have to freshly call it
                            account._state.nonceUsed = true;
                            account._state.pending -= value;
                            console.log("Transfer of " + value + " was successful. Balance of account " + number + " now " + (account._state.available + account._state.pending) + ".");
                        } else {
                            console.log("Transfer from account " + number + " failed (txHash = \"" + receipt.transactionHash + "\").");
                        }
                    });
            });
        });
        return "Initiating transfer.";
    }

    this.withdraw = (value, number) => {
        number = number ? number : 1;
        var accounts = that.accounts.showAccounts();
        if (accounts.length < number) {
            throw "Account " + number + " not available! Please add more.";
        }
        var account = accounts[number - 1];

        var state = account._simulateBalances();
        if (value > state.available + state.pending)
            throw "Requested withdrawal amount of " + value + " exceeds account " + number + "'s balance of " + (state.available + state.pending) + ".";

        var wait = away();
        var seconds = Math.ceil(wait / 1000);
        var plural = seconds == 1 ? "" : "s";
        if (value > state.available) {
            var timer = setTimeout(() => {
                that.withdraw(value);
            }, wait);
            return "Withdrawal on account + " + number + " queued. Please wait " + seconds + " second" + plural + ", for the release of your funds...";
        }
        if (state.nonceUsed) {
            var timer = setTimeout(() => {
                that.withdraw(value);
            }, wait);
            return "Withdrawal on account " + number + " queued. Please wait " + seconds + " second" + plural + ", until the next epoch...";
        }

        if (2000 > wait) { // withdrawals will take <= 2 seconds (actually, more like 1)...
            var timer = setTimeout(() => {
                that.withdraw(value);
            }, wait);
            return "Initiating withdrawal.";
        }

        zsc.methods.simulateAccounts([account.keypair['y']], this._getEpoch()).call({}, (error, result) => {
            var simulated = result[0];

            var u = maintenance.gEpoch(state.lastRollOver);
            var proof = service.proveBurn(simulated[0], simulated[1], account.keypair['y'], value, state.lastRollOver, account.keypair['x'], state.available - value, (proof) => {
                zsc.methods.burn(account.keypair['y'], value, u, proof).send({ from: home, gas: 547000000 })
                    .on('transactionHash', (hash) => {
                        console.log("Withdrawal submitted (txHash = \"" + hash + "\").");
                    })
                    .on('receipt', (receipt) => {
                        if (receipt.status) {
                            account._state = account._simulateBalances(); // have to freshly call it
                            account._state.nonceUsed = true;
                            account._state.pending -= value;
                            console.log("Withdrawal of " + value + " was successful. Balance of account " + number + " now " + (account._state.available + account._state.pending) + ".");
                        } else {
                            console.log("Withdrawal from account " + number + " failed (txHash = \"" + hash + "\").");
                        }
                    });
            });
        });
        return "Initiating withdrawal.";
    }
}


module.exports = client;