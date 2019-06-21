const { GeneratorParams, FieldVector } = require('./algebra.js');
const bn128 = require('../../utils/bn128.js');

class AnonProver {
    constructor() {
        this.generateProof = (statement, witness) => {
            var size = statement['y'].length;
            var params = new GeneratorParams(size);

            var rA = bn128.randomScalar();
            var rB = bn128.randomScalar();
            var rC = bn128.randomScalar();
            var rD = bn128.randomScalar();

            var a = Array.from({ length: 2 }).map(() => Array.from({ length: size - 1 }).map(bn128.randomScalar));
            a = a.map((a_i) => {
                a_i.unshift(a_i.reduce((accum, cur) => accum.redAdd(cur), new BN(0).toRed(bn128.q)).redNeg());
                return new FieldVector(a_i);
            });
            var b = Array.from({ length: 2 }).map((_, i) => new FieldVector(Array.from({ length: size }).map((_, j) => witness['index'][i] == j ? new BN(1).toRed(bn128.q) : new BN(0).toRed(bn128.q))));
            var c = a.map((a_i, i) => a_i.hadamard(b[i].times(new BN(2).toRed(bn128.q)).negate().plus(new BN(1).toRed(bn128.q))));
            var d = a.map((a_i) => a_i.hadamard(a_i).negate())

            var A = params.commit(a[0], a[1], rA);
            var B = params.commit(b[0], b[1], rB);
            var C = params.commit(c[0], c[1], rC);
            var D = params.commit(d[0], d[1], rD);

            var inOutG = params.getG().mul(witness['rho']);
            var gG = g.multiply(witness['sigma']);

            statement['CLn'] = new GeneratorVector(statement['CLn'].map((point) => bn128.unserialize(point)));
            statement['CRn'] = new GeneratorVector(statement['CRn'].map((point) => bn128.unserialize(point)));
            statement['L'] = new GeneratorVector(statement['L'].map((point) => bn128.unserialize(point)));
            statement['R'] = bn128.unserialize(statement['R']);
            statement['y'] = new GeneratorVector(statement['y'].map((point) => bn128.unserialize(point)));

            var CLnG = statement['CLn'].commit(a[0]).add(statement['y'].getVector().get(witness['index'][0]).mul(witness['pi']));
            var CRnG = statement['CRn'].commit(a[0]).add(params.getG().mul(witness['pi']));
            var LG = a.map((a_i, i) => bn128.circularConvolution(a_i, statement['L']).extract(0).add(statement['y'].shift(witness['index'][i]).flip().extract(0).times(witness['rho'])));
            var yG = a.map((a_i, i) => bn128.circularConvolution(a_i, statement['y']).extract(0).add(statement['y'].shift(witness['index'][i]).flip().extract(0).times(witness['sigma'])));
        };
    }
}