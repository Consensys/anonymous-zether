const { AbiCoder } = require('web3-eth-abi');
const BN = require('bn.js');

const { GeneratorParams, FieldVector, Convolver } = require('../algebra.js');
const bn128 = require('../../utils/bn128.js');
const utils = require('../../utils/utils.js');

class AnonProof {
    constructor() {
        this.serialize = () => {
            var result = "0x";
            result += bn128.representation(this.P).slice(2);
            result += bn128.representation(this.Q).slice(2);
            result += bn128.representation(this.U).slice(2);
            result += bn128.representation(this.V).slice(2);
            result += bn128.representation(this.X).slice(2);
            result += bn128.representation(this.Y).slice(2);
            result += bn128.representation(this.CLnG).slice(2);
            result += bn128.representation(this.CRnG).slice(2);
            result += bn128.representation(this.DG).slice(2);
            result += bn128.representation(this.gG).slice(2);
            this.f.forEach((f_i) => {
                f_i.getVector().forEach((f_ij) => {
                    result += bn128.bytes(f_ij).slice(2);
                });
            });
            this.CG.forEach((CG_i) => {
                CG_i.getVector().forEach((CG_ij) => {
                    result += bn128.representation(CG_ij).slice(2);
                });
            });
            this.yG.forEach((yG_i) => {
                yG_i.getVector().forEach((yG_ij) => {
                    result += bn128.representation(yG_ij).slice(2);
                });
            });
            result += bn128.bytes(this.zP).slice(2);
            result += bn128.bytes(this.zU).slice(2);
            result += bn128.bytes(this.zX).slice(2);

            return result;
        };
    }
}

class AnonProver {
    constructor() {
        var abiCoder = new AbiCoder();

        var params = new GeneratorParams();

        this.generateProof = (statement, witness, salt) => {
            var size = statement['y'].length();
            if (params.size() < size) {
                params.extend(size);
            } // one-off cost when a "new record" size is used.

            var rP = bn128.randomScalar();
            var rQ = bn128.randomScalar();
            var rU = bn128.randomScalar();
            var rV = bn128.randomScalar();
            var rX = bn128.randomScalar();
            var rY = bn128.randomScalar();
            var p = Array.from({ length: 2 }).map(() => Array.from({ length: size - 1 }).map(bn128.randomScalar));
            p = p.map((p_i) => {
                p_i.unshift(new FieldVector(p_i).sum().redNeg());
                return new FieldVector(p_i);
            });
            var q = Array.from({ length: 2 }).map((_, i) => new FieldVector(Array.from({ length: size }).map((_, j) => witness['index'][i] == j ? new BN(1).toRed(bn128.q) : new BN(0).toRed(bn128.q))));
            var u = p.map((p_i, i) => p_i.hadamard(q[i].times(new BN(2).toRed(bn128.q)).negate().plus(new BN(1).toRed(bn128.q))));
            var v = p.map((p_i) => p_i.hadamard(p_i).negate())

            var proof = new AnonProof();
            proof.P = params.commit(p[0], p[1], rP);
            proof.Q = params.commit(q[0], q[1], rQ);
            proof.U = params.commit(u[0], u[1], rU);
            proof.V = params.commit(v[0], v[1], rV);

            proof.DG = statement['D'].mul(witness['sigma']);
            proof.gG = params.getG().mul(witness['sigma']);

            proof.CLnG = statement['CLn'].commit(p[0]).add(statement['CLn'].getVector()[witness['index'][0]].add(params.getG().mul(-witness['bDiff'])).mul(witness['sigma']));
            proof.CRnG = statement['CRn'].commit(p[0]).add(statement['CRn'].getVector()[witness['index'][0]].mul(witness['sigma']));
            var convolver = new Convolver();
            proof.CG = p.map((p_i, i) => convolver.convolution(p_i, statement['C']).add(statement['y'].shift(witness['index'][i]).extract(0).times(witness['sigma'].mul(witness['r']))));
            proof.yG = p.map((p_i, i) => convolver.convolution(p_i, statement['y']).add(statement['y'].shift(witness['index'][i]).extract(0).times(witness['sigma'])));

            var cycler = p.map((p_i) => new FieldVector(Array.from({ length: 2 }).map((_, j) => p_i.extract(j).sum())));
            proof.X = params.commit(cycler[0].hadamard(cycler[1]).extract(0), cycler[0].hadamard(cycler[1]).extract(1), rX);
            proof.Y = params.commit(cycler[witness['index'][1] % 2].extract(0), cycler[witness['index'][0] % 2].extract(1), rY);

            proof.challenge = utils.hash(abiCoder.encodeParameters([ // diverting with practice to just include this in the proof, but...
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2][2][]',
                'bytes32[2][2][]',
            ], [
                bn128.bytes(salt),
                bn128.serialize(proof.P),
                bn128.serialize(proof.Q),
                bn128.serialize(proof.U),
                bn128.serialize(proof.V),
                bn128.serialize(proof.X),
                bn128.serialize(proof.Y),
                bn128.serialize(proof.CLnG),
                bn128.serialize(proof.CRnG),
                bn128.serialize(proof.DG),
                bn128.serialize(proof.gG),
                proof.CG[0].getVector().map((point, i) => [point, proof.CG[1].getVector()[i]].map(bn128.serialize)),
                proof.yG[0].getVector().map((point, i) => [point, proof.yG[1].getVector()[i]].map(bn128.serialize)),
            ]));

            proof.f = p.map((p_i, i) => new FieldVector(p_i.add(q[i].times(proof['challenge'])).getVector().slice(1)));
            proof.zP = rQ.redMul(proof.challenge).redAdd(rP);
            proof.zU = rU.redMul(proof.challenge).redAdd(rV);
            proof.zX = rY.redMul(proof.challenge).redAdd(rX);

            return proof;
        };
    }
}

module.exports = AnonProver;