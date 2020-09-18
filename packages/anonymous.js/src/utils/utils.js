const bn128 = require('./bn128.js')
const BN = require('bn.js')
const { soliditySha3 } = require('web3-utils');
const ABICoder = require('web3-eth-abi');

const utils = {};

utils.sign = (address, keypair) => {
    const k = bn128.randomScalar();
    const K = bn128.curve.g.mul(k);
    const c = utils.hash(ABICoder.encodeParameters([
        'address',
        'bytes32[2]',
        'bytes32[2]',
    ], [
        address,
        bn128.serialize(keypair['y']),
        bn128.serialize(K),
    ]));

    const s = c.redMul(keypair['x']).redAdd(k);
    return [bn128.bytes(c), bn128.bytes(s)];
}

utils.createAccount = () => {
    const x = bn128.randomScalar();
    const y = bn128.curve.g.mul(x);
    return { 'x': x, 'y': y };
};

utils.readBalance = (CL, CR, x) => {
    CL = bn128.deserialize(CL);
    CR = bn128.deserialize(CR);
    const gB = CL.add(CR.mul(x.redNeg()));

    let accumulator = bn128.zero;
    for (let i = 0; i < bn128.B_MAX; i++) {
        if (accumulator.eq(gB)) return i;
        accumulator = accumulator.add(bn128.curve.g);
    }
};

utils.mapInto = (seed) => { // seed is flattened 0x + hex string
    const seed_red = new BN(seed.slice(2), 16).toRed(bn128.p);
    const p_1_4 = bn128.curve.p.add(new BN(1)).div(new BN(4));
    while (true) {
        const y_squared = seed_red.redPow(new BN(3)).redAdd(new BN(3).toRed(bn128.p));
        const y = y_squared.redPow(p_1_4);
        if (y.redPow(new BN(2)).eq(y_squared)) {
            return bn128.curve.point(seed_red.fromRed(), y.fromRed());
        }
        seed_red.redIAdd(new BN(1).toRed(bn128.p));
    }
};

utils.gEpoch = (epoch) => {
    return utils.mapInto(soliditySha3("Zether", epoch));
};

utils.u = (epoch, x) => {
    return utils.gEpoch(epoch).mul(x);
};

utils.hash = (encoded) => { // ags are serialized
    return new BN(soliditySha3(encoded).slice(2), 16).toRed(bn128.q);
};

module.exports = utils;