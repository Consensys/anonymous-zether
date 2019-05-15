const maintenance = require("./utils/maintenance.js");

var Account = function Account() {
  var register = (zsc, keypair, number) => {
    zsc.methods
      .register(keypair["y"])
      .send({ from: home, gas: 5470000 }, (error, transactionHash) => {
        var timer = setTimeout(() => {
          console.log(
            "Registration of account " +
              number +
              ' appears to be taking a while... Check the transaction hash "' +
              transactionHash +
              '". Do not use this account without registration!'
          );
        }, 5000);
        that._callbacks[transactionHash] = () => {
          clearTimeout(timer);
          console.log("Registration of account " + number + " successful.");
        };
      });
  };

  function account() {
    this.keypair = undefined;
    this._state = new (function() {
      // don't touch this...
      this.available = 0;
      this.pending = 0;
      this.nonceUsed = 0;
      this.lastRollOver = 0;
    })();
    this._simulateBalances = timestamp => {
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
  }

  var accounts = [];
  this.addAccount = (zsc, keypair) => {
    // a dict of the form { 'x': x, 'y': y } plus state stuff.
    // assuming that it is actually a proper keypair.
    if (keypair === undefined) {
      throw "Please specify the keypair of the account you'd like to add.";
    }
    var temp = new account();
    temp.keypair = keypair;
    var number = accounts.push(temp);
    register(zsc, keypair, number);
    return "Account " + number + " added.";
  };

  this.newAccount = zsc => {
    var keypair = maintenance.createAccount();
    var temp = new account();
    temp.keypair = keypair;
    var number = accounts.push(temp);
    register(zsc, keypair, number);
    return "Account " + number + " generated."; // won't print it out for now.
  };

  this.showAccounts = () => {
    return accounts;
  };
};

module.exports = Account;
