const BN = require('bn.js')
const EC = require('elliptic')
const crypto = require('crypto')

const FIELD_MODULUS = new BN("21888242871839275222246405745257275088696311157297823662689037894645226208583", 10);
const GROUP_MODULUS = new BN("21888242871839275222246405745257275088548364400416034343698204186575808495617", 10);
const B_MAX = 4294967295;

const bn128 = {}

// The elliptic.js curve object
bn128.curve = new EC.curve.short({
    a: '0',
    b: '3',
    p: FIELD_MODULUS.toString(16),
    n: GROUP_MODULUS.toString(16),
    gRed: false,
    g: ['77da99d806abd13c9f15ece5398525119d11e11e9836b2ee7d23f6159ad87d4', '1485efa927f2ad41bff567eec88f32fb0a0f706588b4e41a8d587d008b7f875'],
});

bn128.fieldReduction = BN.red(bn128.curve.p);
bn128.groupReduction = BN.red(bn128.curve.n);

// Get a random BN in the bn128 curve group's reduction context
bn128.randomGroupScalar = () => {
    return "0x" + new BN(crypto.randomBytes(32), 16).toRed(bn128.groupReduction).toString(16);
}

bn128.B_MAX = B_MAX;

bn128.bn128Add = (p1, p2) => {
    if (p1[0] == "0x0000000000000000000000000000000000000000000000000000000000000000") {
        return p2
    }
    if (p2[0] == "0x0000000000000000000000000000000000000000000000000000000000000000") {
        return p1
    }
    p1 = bn128.curve.point(p1[0].slice(2), p1[1].slice(2))
    p2 = bn128.curve.point(p2[0].slice(2), p2[1].slice(2))
    var p = p1.add(p2)
    return ["0x" + p.getX().toString(16).padStart(64, '0'), "0x" + p.getY().toString(16).padStart(64, '0')]
}

module.exports = bn128;