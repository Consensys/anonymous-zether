const maintenance = require('../utils/maintenance.js');
const { soliditySha3 } = require('web3-utils');

class BurnProver {
    constructor() {
        var g = maintenance.mapInto(soliditySha3("G"));
        var h = maintenance.mapInto(soliditySha3("V"));
        var gs = [...Array(32).keys()].map((i) => maintenance.mapInto(soliditySha3("G", i)));
        var hs = [...Array(32).keys()].map((i) => maintenance.mapInto(soliditySha3("H", i)));

        this.generateProof = (statement, witness) => {

        }
    }
}

module.exports = BurnProver;