var version = require("../package.json").version;
var Account = require("./account");

var AZ = function AZ() {
  this.version = version;
  this.account = new Account(this);
};

AZ.version = version;
AZ.modules = {
  Account: Account
};

module.exports = AZ;
