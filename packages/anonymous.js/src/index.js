var version = require("../package.json").version;
var Client = require("./client");

var AZ = function AZ() {
  this.version = version;
  this.client = new Client(this);
};

AZ.version = version;
AZ.modules = {
  Client: Client
};

module.exports = AZ;
