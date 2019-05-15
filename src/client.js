const maintenance = require('./utils/maintenance.js');
const service = require('./utils/service.js');

function client(zsc) { // todo: how to ascertain the address(es) that the user wants to register against?
    if (zsc === undefined) {
        throw "Please provide an argument pointing to a deployed ZSC contract!";
    }
    var that = this;

    var home = "0xed9d02e382b34818e88b88a309c7fe71e65f419d";

    this._callbacks = {};
    zsc.events.allEvents({}, (error, event) => {
        if (event.transactionHash in that._callbacks) {
            that._callbacks[event.transactionHash]();
            delete that._callbacks[event.transactionHash];
        }
    }) // a sort of hack to respond to events.

    this._epochLength = undefined;
    zsc.methods.epochLength().call({}, (error, result) => {
        that._epochLength = result;
    }); // how to prevent use until this thing has been properly populated?
    this._getEpoch = function(timestamp) { // timestamp is in ms; so is epochLength.
        return Math.floor((timestamp === undefined ? (new Date).getTime() : timestamp) / this._epochLength);
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
        return updated;
    }

    this._state = new function() { // don't touch this...
        this.available = 0;
        this.pending = 0;
        this.nonceUsed = 0;
        this.lastRollOver = 0;
    }

    this.balance = () => {
        return this._state.available + this._state.pending;
    }

    this.accounts = new function() { // strange construction but works, revisit
        var register = (account, number) => {
            zsc.methods.register(account['y']).send({ from: home, gas: 5470000 }, (error, transactionHash) => {
                var timer = setTimeout(() => {
                    console.log("Registration of account " + number + " appears to be taking a while... Check the transaction hash \"" + transactionHash + "\". Do not use this account without registration!");
                }, 5000);
                that._callbacks[transactionHash] = () => {
                    clearTimeout(timer);
                    console.log("Registration of account " + number + " successful.");
                };
            });
        }

        var accounts = [];
        this.addAccount = (account) => { // a dict of the form { 'x': x, 'y': y }.
            // assuming that it is actually a proper keypair.
            if (account === undefined) {
                throw "Please specify the account you'd like to add.";
            }
            var number = accounts.push(account);
            register(account, number);
            return "Account " + number + " added.";
        }
        this.newAccount = () => {
            var account = maintenance.createAccount();
            var number = accounts.push(account);
            register(account, number);
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
        zsc.methods.fund(accounts[number - 1]['y'], value).send({ from: home, gas: 5470000 }, (error, transactionHash) => {
            var timer = setTimeout(() => {
                console.log("Deposit appears to be taking a while... Check the transaction hash \"" + transactionHash + "\".");
            }, 5000);
            that._callbacks[transactionHash] = () => {
                clearTimeout(timer);
                that._state = that._simulateBalances(); // have to freshly call it
                that._state.pending += value;
                console.log("Deposit of " + value + " successful. Balance is now " + (that._state.available + that._state.pending) + ".");
            }
        });
        return "Initiating deposit.";
    }



    this.withdraw = (value, number) => {
        number = number ? number : 1;
        var accounts = that.accounts.showAccounts();
        if (accounts.length < number) {
            throw "Account " + number + " not available! Please add more.";
        }

        var state = this._simulateBalances();
        if (value > state.available + state.pending)
            throw "Requested withdrawal amount of " + value + " exceeds account balance of " + (state.available + state.pending) + ".";

        var wait = away();
        var seconds = Math.ceil(wait / 1000);
        var plural = seconds == 1 ? "" : "s";
        if (value > state.available) {
            var timer = setTimeout(() => {
                that.withdraw(value);
            }, wait);
            return "Your withdrawal has been queued. Please wait " + seconds + " second" + plural + ", for the release of your funds...";
        }
        if (state.nonceUsed) {
            var timer = setTimeout(() => {
                that.withdraw(value);
            }, wait);
            return "Your withdrawal has been queued. Please wait " + seconds + " second" + plural + ", until the next epoch...";
        }

        if (2000 > wait) { // withdrawals will take <= 2 seconds (actually, more like 1)...
            var timer = setTimeout(() => {
                that.withdraw(value);
            }, wait);
            return "Initiating withdrawal.";
        }

        zsc.methods.simulateAccounts([accounts[number - 1]['y']], this._getEpoch()).call({}, (error, result) => {
            var simulated = result[0];

            var proof = service.proveBurn(simulated[0], simulated[1], accounts[number - 1]['y'], value, state.lastRollOver, accounts[number - 1]['x'], state.available - value);
            var u = maintenance.gEpoch(state.lasRollOver);

            zsc.methods.burn(accounts[number - 1]['y'], value, u, proof).send({ from: home, gas: 547000000 }, (error, transactionHash) => {
                var timer = setTimeout(() => {
                    console.log("Withdrawal appears to be taking a while... Check the transaction hash \"" + transactionHash + "\".");
                }, 5000);
                that._callbacks[transactionHash] = () => {
                    clearTimeout(timer);
                    that._state = that._simulateBalances(); // have to freshly call it
                    that._state.nonceUsed = true;
                    that._state.pending -= value;
                    console.log("Withdrawal of " + value + " was successful. Balance now " + (that._state.available + _state.state.pending) + ".");
                }
            });
        });
        return "Initiating withdrawal.";
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

}


module.exports = client;