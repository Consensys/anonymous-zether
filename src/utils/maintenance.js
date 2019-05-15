const bn128 = require('./bn128.js')
const BN = require('bn.js')

const maintenance = {}

bn128.determinePublicKey = x => {
    let x_bn = new BN(x.slice(2), 16).toRed(bn128.groupReduction);
    let y_point = bn128.curve.g.mul(x_bn);
    return ["0x" + y_point.getX().toString(16).padStart(64, '0'), "0x" + y_point.getY().toString(16).padStart(64, '0')];
}

// Brute-force decrypt balance for [0, B_MAX]
// not using a "start" parameter for now... revisit.
bn128.readBalance = (gbyr, gr, x) => {
    var gr_point = bn128.curve.point(gr[0].slice(2), gr[1].slice(2));
    var gbyr_point = bn128.curve.point(gbyr[0].slice(2), gbyr[1].slice(2));
    var x_bn = new BN(x.slice(2), 16).toRed(bn128.groupReduction)

    // not handling the case of the 0 point... shouldn't be necessary. revisit.
    let gb = gbyr.add(gr.mul(x_bn).neg())

    let accumulator = bn128.curve.g.mul(0);
    for (var i = 0; i < bn128.B_MAX; i++) {
        if (accumulator.eq(gb)) {
            return i;
        }
        accumulator = accumulator.add(bn128.curve.g);
    }
}

maintenance.createAccount = () => {
    let x = bn128.randomGroupScalar();
    let y = bn128.determinePublicKey(x);
    return { 'x': x, 'y': y };
}

module.exports = maintenance