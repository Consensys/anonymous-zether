const BN = require('bn.js')
const EC = require('elliptic')
const crypto = require('crypto')

const FIELD_MODULUS = new BN("30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47", 16);
const GROUP_MODULUS = new BN("30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001", 16);
const B_MAX = 4294967295;
const empty = "0x0000000000000000000000000000000000000000000000000000000000000000";
const bn128 = {};

bn128.curve = new EC.curve.short({
    a: '0',
    b: '3',
    p: FIELD_MODULUS,
    n: GROUP_MODULUS,
    gRed: false,
    g: ['077da99d806abd13c9f15ece5398525119d11e11e9836b2ee7d23f6159ad87d4', '01485efa927f2ad41bff567eec88f32fb0a0f706588b4e41a8d587d008b7f875'],
    // bizarre that g is set equal to one of the pedersen base elements. actually in theory not necessary (though the verifier would have to change also).
});

bn128.zero = bn128.curve.g.mul(0);

bn128.p = BN.red(bn128.curve.p);
bn128.q = BN.red(bn128.curve.n);

bn128.randomScalar = () => new BN(crypto.randomBytes(32), 16).toRed(bn128.q);
bn128.bytes = (i) => "0x" + i.toString(16, 64);
bn128.serialize = (point) => { // differs from point.encode('hex'). ethereum-compatible
    if (point.x === null && point.y === null) return [empty, empty];
    return [bn128.bytes(point.getX()), bn128.bytes(point.getY())];
};
bn128.representation = (point) => { // essentially for serializing proofs...
    if (point.x === null && point.y === null) return empty + empty.slice(2);
    return bn128.bytes(point.getX()) + bn128.bytes(point.getY()).slice(2);
};
bn128.deserialize = (serialization) => {
    if (serialization[0] === empty && serialization[1] === empty) return bn128.zero;
    return bn128.curve.point(serialization[0].slice(2), serialization[1].slice(2)); // no check if valid curve point?
};

bn128.B_MAX = B_MAX;

module.exports = bn128;