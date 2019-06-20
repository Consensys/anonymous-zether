const bn128 = require('./bn128.js')
const BN = require('bn.js')
const { soliditySha3 } = require('web3-utils');

const maintenance = {}

maintenance.determinePublicKey = (x) => {
    return bn128.canonicalRepresentation(bn128.curve.g.mul(x));
}

// no "start" parameter for now.
// CL and CR are "flat", x is a BN.
maintenance.readBalance = (CL, CR, x) => {
    var CLPoint, CRPoint;
    if (CL[0] == "0x0000000000000000000000000000000000000000000000000000000000000000" && CL[1] == "0x0000000000000000000000000000000000000000000000000000000000000000") {
        CLPoint = bn128.curve.g.mul(0);
    } else {
        CLPoint = bn128.curve.point(CL[0].slice(2), CL[1].slice(2));
    }
    if (CR[0] == "0x0000000000000000000000000000000000000000000000000000000000000000" && CR[1] == "0x0000000000000000000000000000000000000000000000000000000000000000") {
        CRPoint = bn128.curve.g.mul(0);
    } else {
        CRPoint = bn128.curve.point(CR[0].slice(2), gr[1].slice(2));
    }

    var gB = CLPoint.add(CRPoint.mul(x.neg()));

    let accumulator = bn128.curve.g.mul(0);
    for (var i = 0; i < bn128.B_MAX; i++) {
        if (accumulator.eq(gB)) {
            return i;
        }
        accumulator = accumulator.add(bn128.curve.g);
    }
}

maintenance.createAccount = () => {
    let x = bn128.randomScalar();
    let y = maintenance.determinePublicKey(x);
    return { 'x': x, 'y': y };
}

maintenance.mapInto = (seed) => {
    var seed_red = seed.toRed(bn128.fieldReduction);
    var p_1_4 = bn128.curve.p.add(new BN(1)).div(new BN(4));
    while (true) {
        var y_squared = seed_red.redPow(new BN(3)).redAdd(new BN(3).toRed(bn128.fieldReduction));
        var y = y_squared.redPow(p_1_4);
        if (y.redPow(new BN(2)).eq(y_squared)) {
            return bn128.curve.point(seed_red, y);
        }
        seed_red.redIAdd(new BN(1).toRed(bn128.fieldReduction));
    }
}

maintenance.gEpoch = (epoch) => {
    return maintenance.mapInto(new BN(soliditySha3("Zether", epoch).slice(2), 16));
}

maintenance.u = (epoch, x) => {
    return bn128.canonicalRepresentation(maintenance.gEpoch(epoch).mul(x));
}

module.exports = maintenance;