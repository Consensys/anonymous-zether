const bn128 = require('./bn128.js')
const BN = require('bn.js')
const { soliditySha3 } = require('web3-utils');

class GeneratorParams {
    constructor(size) {
        var g = maintenance.mapInto(soliditySha3("G"));
        var h = maintenance.mapInto(soliditySha3("V"));
        var gs = [...Array(size).keys()].map((i) => maintenance.mapInto(soliditySha3("G", i)));
        var hs = [...Array(size).keys()].map((i) => maintenance.mapInto(soliditySha3("H", i)));

        this.commit = (gExp, hExp, blinding) => {
            var result = h.mul(blinding);
            gs.forEach((g, i) => {
                result = result.add(g.mul(gExp[i]));
            })
            hs.forEach((h, i) => { // swap the order and enclose this in an if (hExp) if block if you want it optional.
                result = result.add(h.mul(hExp[i]));
            })
        }
    }
}

module.exports = GeneratorParams;