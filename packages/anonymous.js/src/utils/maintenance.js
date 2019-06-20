const bn128 = require('./bn128.js')
const BN = require('bn.js')
const { soliditySha3 } = require('web3-utils');

const maintenance = {}

maintenance.determinePublicKey = (x) => { // x is already a BN
    let y_point = bn128.curve.g.mul(x);
    return ["0x" + y_point.getX().toString(16).padStart(64, '0'), "0x" + y_point.getY().toString(16).padStart(64, '0')];
}

// Brute-force decrypt balance for [0, B_MAX]
// not using a "start" parameter for now... revisit.
maintenance.readBalance = (gbyr, gr, x) => {
    var gbyr_point, gr_point;
    if (gbyr[0] == "0x0000000000000000000000000000000000000000000000000000000000000000" && gbyr[1] == "0x0000000000000000000000000000000000000000000000000000000000000000") {
        gbyr_point = bn128.curve.g.mul(0);
    } else {
        gbyr_point = bn128.curve.point(gbyr[0].slice(2), gbyr[1].slice(2));
    }
    if (gbyr[0] == "0x0000000000000000000000000000000000000000000000000000000000000000" && gbyr[1] == "0x0000000000000000000000000000000000000000000000000000000000000000") {
        gr_point = bn128.curve.point(gbyr[0].slice(2), gbyr[1].slice(2));
    } else {
        var gr_point = bn128.curve.point(gr[0].slice(2), gr[1].slice(2));
    }
    var x_bn = new BN(x.slice(2), 16).toRed(bn128.groupReduction);

    // not handling the case of the 0 point... shouldn't be necessary. revisit.
    let gb = gbyr_point.add(gr_point.mul(x_bn).neg());

    let accumulator = bn128.curve.g.mul(0);
    for (var i = 0; i < bn128.B_MAX; i++) {
        if (accumulator.eq(gb)) {
            return i;
        }
        accumulator = accumulator.add(bn128.curve.g);
    }
}

maintenance.createAccount = () => {
    let x = bn128.randomScalar();
    let y = maintenance.determinePublicKey(x);
    return { 'x': bn128.toString(x), 'y': y };
}

maintenance.gEpoch = (epoch) => { // a 0x + hex string
    var seed = soliditySha3("Zether", epoch);
    var seed_bn = new BN(seed.slice(2), 16).toRed(bn128.fieldReduction);
    var p_1_4 = bn128.curve.p.add(new BN(1)).div(new BN(4));
    while (true) {
        var y_squared = seed_bn.redPow(new BN(3)).redAdd(new BN(3).toRed(bn128.fieldReduction));
        var y = y_squared.redPow(p_1_4);
        if (y.redPow(new BN(2)).eq(y_squared)) {
            return bn128.curve.point(seed_bn.toString(16), y.toString(16));
        }
        seed_bn.redIAdd(new BN(1).toRed(bn128.fieldReduction));
    }
}

maintenance.u = (epoch, x) => {
    return bn128.canonicalRepresentation(maintenance.gEpoch(epoch).mul(x));
}

module.exports = maintenance;