/* beautify ignore:start */
var zscContract = web3.eth.contract([{"constant":false,"inputs":[{"name":"outL","type":"bytes32[2]"},{"name":"inL","type":"bytes32[2]"},{"name":"inOutR","type":"bytes32[2]"},{"name":"y","type":"bytes32[2]"},{"name":"yBar","type":"bytes32[2]"},{"name":"proof","type":"bytes"},{"name":"signature","type":"bytes32[3]"}],"name":"transfer","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"name":"y","type":"bytes32[2]"}],"name":"register","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"name":"","type":"bytes32"}],"name":"ethAddrs","outputs":[{"name":"","type":"address"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"y","type":"bytes32[2]"},{"name":"bTransfer","type":"uint256"}],"name":"fund","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[{"name":"","type":"bytes32"},{"name":"","type":"uint256"},{"name":"","type":"uint256"}],"name":"acc","outputs":[{"name":"","type":"bytes32"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"name":"","type":"bytes32"}],"name":"ctr","outputs":[{"name":"","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":true,"inputs":[{"name":"","type":"bytes32"},{"name":"","type":"uint256"},{"name":"","type":"uint256"}],"name":"pTransfers","outputs":[{"name":"","type":"bytes32"}],"payable":false,"stateMutability":"view","type":"function"},{"constant":false,"inputs":[{"name":"y","type":"bytes32[2]"},{"name":"bTransfer","type":"uint256"},{"name":"proof","type":"bytes"},{"name":"signature","type":"bytes32[3]"}],"name":"burn","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":false,"inputs":[{"name":"y","type":"bytes32[2]"}],"name":"rollOver","outputs":[],"payable":false,"stateMutability":"nonpayable","type":"function"},{"constant":true,"inputs":[],"name":"domainHash","outputs":[{"name":"","type":"bytes32"}],"payable":false,"stateMutability":"view","type":"function"},{"inputs":[{"name":"_coin","type":"address"},{"name":"_chainId","type":"uint256"}],"payable":false,"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":false,"name":"registerer","type":"bytes32[2]"},{"indexed":false,"name":"addr","type":"address"}],"name":"RegistrationOccurred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"roller","type":"bytes32[2]"}],"name":"RollOverOccurred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"funder","type":"bytes32[2]"}],"name":"FundOccurred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"burner","type":"bytes32[2]"}],"name":"BurnOccurred","type":"event"},{"anonymous":false,"inputs":[{"indexed":false,"name":"sender","type":"bytes32[2]"},{"indexed":false,"name":"recipient","type":"bytes32[2]"}],"name":"TransferOccurred","type":"event"}]);
/* beautify ignore:end */

function _deployZSC(coin) {
    var zsc = zscContract.new(
        coin,
        10, {
            from: web3.eth.accounts[0],
            data: '',
            gas: '4700000'
        },
        function(e, contract) {
            if (typeof contract.address !== 'undefined') {
                console.log('Contract mined! address: ' + contract.address + ' transactionHash: ' + contract.transactionHash);
            }
        })
    return zsc;
}

function _recoverZSC(address) {
    var zsc = zscContract.at(address);
    return zsc;
}

var demo = (function() {
    return {
        deployZSC: function(coin) {
            return _deployZSC(coin);
        },
        recoverZSC: function(address) {
            return _recoverZSC(address);
        },
    };
})();


function tracker(zsc) {
    function state() {
        this.acc = [
            ['0x0000000000000000000000000000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000000000000000000000000000'],
            ['0x0000000000000000000000000000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000000000000000000000000000']
        ];
        this.available = 0; // reflects WOULD-BE value in acc (i.e., if rollOver were called). do not touch this manually
        this.pending = 0; // represents an estimate of pTransfers alone. this is used to speed up peeking when transfers are received
        this.nonceUsed = false;
    }
    this.state = new state();

    var that = this;

    var zsc = zsc;
    var keypair = zether.createAccount(); // private
    var yHash = web3.sha3(keypair['y'][0].slice(2) + keypair['y'][1].slice(2), { encoding: 'hex' });
    var friends = {};
    var epochLength = zsc.epochLength();
    var lastRollOver = 0; // would it make sense to just pull this directly every time...?!

    var currentEpoch = function() { return Math.floor(eth.blockNumber / epochLength); }

    var match = function(address, candidate) {
        return address[0] == candidate[0] && address[1] == candidate[1];
    } // consider refactoring / eliminating this, e.g. using JSON.stringify

    var simulateRollOver = function(address) { // "baby" version of the below which will be used for _foreign_ accounts.
        var yHash = web3.sha3(address[0].slice(2) + address[1].slice(2), { encoding: 'hex' });
        var state = new state();
        state.acc = [
            [zsc.acc(yHash, 0, 0), zsc.acc(yHash, 0, 1)],
            [zsc.acc(yHash, 1, 0), zsc.acc(yHash, 1, 1)]
        ];
        if (zsc.lastRollOver(yHash) < currentEpoch()) {
            var pTransfers = [
                [zsc.pending(yHash, 0, 0), zsc.pending(yHash, 0, 1)],
                [zsc.pending(yHash, 1, 0), zsc.pending(yHash, 1, 1)]
            ];
            state.acc = [zether.add(acc[0], pTransfers[0]), zether.add(acc[1], pTransfers[1])];
        }
    }

    this.simulateRollOver = function() {
        var state = new state();
        state.acc = this.state.acc.slice(); // copy
        state.available = this.state.available;
        state.pending = this.state.pending;
        state.nonceUsed = this.state.nonceUsed;

        if (lastRollOver < currentEpoch()) {
            var pTransfers = [
                [zsc.pending(yHash, 0, 0), zsc.pending(yHash, 0, 1)],
                [zsc.pending(yHash, 1, 0), zsc.pending(yHash, 1, 1)]
            ];
            state.acc = [zether.add(acc[0], pTransfers[0]), zether.add(acc[1], pTransfers[1])];
            state.available += state.pending;
            state.pending = 0;
            state.nonceUsed = false; // only so that this can
        }
        return state;
    }
    this.confirmRollOver = function(state) { // not sure this will be ultimately necessary
        this.state = state;
        lastRollOver = currentEpoch();
    }

    zsc.TransferOccurred(function(error, event) { // automatically watch for incoming transfers
        if (error) {
            console.log("Error: " + error);
        } else {
            for (var party in event.args['parties']) {
                if (that.mine(party)) {
                    that.rollOver(that.simulateRollOver());
                    if (that.check()) // if rollOver happens remotely, will mimic it locally, and start from 0
                        console.log("Transfer received! New balance is " + (that.available + that.pending) + ".");
                    // interesting: impossible even to know who sent you funds.
                    // could always report back msg.sender, but that means nothing basically. can always send from different eth address
                    break;
                }
            }
        }
    });

    // todo: add a way to generate throwaway addresses (for receiving), as well as to consolidate throwaways.

    this.me = function() {
        return keypair.y
    }

    this.secret = function() {
        return keypair.x;
    }

    this.mine = function(address) { // only used by callbacks...
        return match(address, keypair['y']);
    }

    this.friend = function(name, address) {
        friends[name] = address;
        return "Friend added.";
    }

    this.check = function() { // returns: did my balance rise?
        var pTransfers = this.pending;
        var pTransfers = [
            [zsc.pending(yHash, 0, 0), zsc.pending(yHash, 0, 1)],
            [zsc.pending(yHash, 1, 0), zsc.pending(yHash, 1, 1)]
        ];
        this.pending = zether.readBalance(pTransfers[0], pTransfers[1], keypair['x'], this.pending, 4294967295);
        return this.pending > pTransfers; // just a shortcut
    }

    this.deposit = function(value) {
        var events = zsc.FundOccurred();
        var timer = setTimeout(function() {
            events.stopWatching();
            console.log("Deposit failed...")
        }, 5000);
        zsc.fund(keypair['y'], value, { from: eth.accounts[0], gas: 5470000 }, function(error, txHash) {
            if (error) {
                console.log("Error: " + error);
            } else {
                events.watch(function(error, event) {
                    if (error) {
                        console.log("Error: " + error);
                    } else if (txHash == event.transactionHash) {
                        clearTimeout(timer);
                        that.available += value;
                        console.log("Deposit of " + value + " was successful. Balance is now " + (that.available + that.pending) + ".");
                        events.stopWatching();
                    }
                });
            }
        });
        return "Initiating deposit.";
    }

    this.transfer = function(name, decoys, value) { // assuming the names of the other people in the anonymity set are being provided?
        var state = this.simulateRollOver();
        if (value > state.available) {
            if (value > state.available + state.pending)
                throw "Requested transfer amount of " + value + " exceeds account balance of " + (state.available + state.pending) + ".";
            else
                throw "Requested transfer amount of " + value + " exceeds presently available balance of " + state.available + ". Please wait until the next rollover (" + (Math.ceil(eth.blockNumber / epochLength) * epochLength - eth.blockNumber) + " blocks away), at which point you'll have " + (state.available + state.pending) + " available.";
        }

        var CL = [];
        var CR = [];
        var y = decoys.concat(this.me()).concat(friends[name]); // not yet shuffled

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

        for (var address in y) { // could use an array.map if i had a better javascript shell.
            var state = simulateRollOver(address);
            CL.push(state.acc[0]);
            CR.push(state.acc[1]);
        }
        var proof = zether.proveTransfer(CL, CR, y, currentEpoch(), keypair['x'], value, state.available - value);
        var events = zsc.TransferOccurred();
        var timer = setTimeout(function() {
            events.stopWatching();
            console.log("Transfer failed...")
        }, 5000);
        zsc.transfer(CL, CR, y, proof['u'], proof['proof'], { from: eth.accounts[0], gas: 5470000 }, function(error, txHash) {
            if (error) {
                console.log("Error: " + error);
            } else {
                events.watch(function(error, event) {
                    // console.log("TransferOccurred event captured")
                    if (error) {
                        console.log("Error: " + error);
                    } else if (txHash == event.transactionHash) {
                        clearTimeout(timer);
                        state.nonceUsed = true;
                        state.pending -= value; // urgent: pending could become NEGATIVE??? might need to adjust readBalance to allow for negative start of range
                        that.confirmRollOver(state);
                        console.log("Transfer of " + value + " was successful. Balance now " + (state.available + state.pending) + ".");
                        events.stopWatching();
                    }
                });
            }
        });
        return "Initiating transfer.";
    }

    this.withdraw = function(value) {
        var state = this.simulateRollOver();
        if (value > state.available) {
            if (value > state.available + state.pending)
                throw "Requested transfer amount of " + value + " exceeds account balance of " + (state.available + state.pending) + ".";
            else
                throw "Requested transfer amount of " + value + " exceeds presently available balance of " + state.available + ". Please wait until the next rollover (" + (Math.ceil(eth.blockNumber / epochLength) * epochLength - eth.blockNumber) + " blocks away), at which point you'll have " + (state.available + state.pending) + " available.";
        }
        if (state.nonceUsed)
            throw "You've already made a withdrawal/transfer during this epoch! Please wait till the next one, " + (Math.ceil(eth.blockNumber / epochLength) * epochLength - eth.blockNumber) + " blocks away.";
        var proof = zether.proveBurn(state.acc[0], state.acc[1], keypair['y'], value, currentEpoch(), keypair['x'], state.available - value);
        var events = zsc.BurnOccurred();
        var timer = setTimeout(function() {
            events.stopWatching();
            console.log("Withdrawal failed...")
        }, 5000);
        zsc.burn(keypair['y'], value, proof['u'], proof['proof'], { from: eth.accounts[0], gas: 5470000 }, function(error, txHash) {
            if (error) {
                console.log("Error: " + error);
            } else {
                events.watch(function(error, event) {
                    if (error) {
                        console.log("Error: " + error);
                    } else if (txHash == event.transactionHash) {
                        clearTimeout(timer);
                        state.nonceUsed = true; // or: after confirming, that.state.nonceUsed = true.
                        state.available -= value;
                        that.confirmRollOver(state);
                        console.log("Withdrawal of " + value + " was successful. Balance now " + (state.available + state.pending) + ".");
                        events.stopWatching();
                    }
                });
            }
        });
        return "Initiating withdrawal.";
    }

    var register = zsc.RegistrationOccurred();
    var timer = setTimeout(function() {
        register.stopWatching();
        console.log("Initial registration failed...!")
    }, 5000);
    register.watch(function(error, event) {
        if (error) {
            console.log("Error: " + error);
        } else if (that.mine(event.args['registerer'])) {
            clearTimeout(timer);
            if (event.args['addr'] != eth.accounts[0]) {
                console.log("Registration process compromised! Create a new tracker and do not use this one.");
            } else {
                console.log("Initial registration successful.");
            }
            register.stopWatching();
        }
    });
    zsc.register(keypair['y'], { from: eth.accounts[0], gas: 5470000 }); // use an event for confirmation?
}