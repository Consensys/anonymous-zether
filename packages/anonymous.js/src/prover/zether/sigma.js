const { AbiCoder } = require('web3-eth-abi');
const BN = require('bn.js');

const { GeneratorParams, GeneratorVector, FieldVector } = require('../algebra.js');
const bn128 = require('../../utils/bn128.js');
const utils = require('../../utils/utils.js');

class SigmaProof {
    constructor() {
        this.serialize = () => {
            var result = "0x";
            result += bn128.bytes(this.challenge).slice(2);
            result += bn128.bytes(this.sX).slice(2);
            result += bn128.bytes(this.sR).slice(2);
            return result;
        };
    }
}

class SigmaProver {
    constructor() {
        var abiCoder = new AbiCoder();

        var params = new GeneratorParams();

        this.generateProof = (statement, witness, salt) => {
            var y = statement['y'][0].getVector()[0];
            var yBar = statement['y'][1].getVector()[0];
            var z = statement['z'];
            var zs = [z.redPow(new BN(2))];
            for (var i = 1; i < 3; i++) {
                zs.push(zs[i - 1].redMul(z));
            }

            var kR = bn128.randomScalar();
            var kX = bn128.randomScalar();

            var Ay = statement['gG'].mul(kX);
            var AD = statement['gG'].mul(kR);
            var Au = utils.gEpoch(statement['epoch']).mul(kX);
            var ADiff = y.add(yBar).mul(kR);
            var At = statement['D'].mul(zs[0].neg()).add(statement['CRn'].mul(zs[1])).add(statement['HR'].mul(witness['w'].mul(zs[2]))).mul(kX);
            var AC = statement['y'].map((y_i) => new GeneratorVector(y_i.times(kR).getVector().slice(1)));

            var proof = new SigmaProof();

            proof.challenge = utils.hash(abiCoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2][2][]',
            ], [
                bn128.bytes(salt),
                bn128.serialize(Ay),
                bn128.serialize(AD),
                bn128.serialize(Au),
                bn128.serialize(ADiff),
                bn128.serialize(At),
                AC[0].getVector().map((point, i) => [point, AC[1].getVector()[i]].map(bn128.serialize)), // unusual---have to transpose
            ]));

            proof.sX = kX.redAdd(proof.challenge.redMul(witness['x']));
            proof.sR = kR.redAdd(proof.challenge.redMul(witness['r']));

            return proof;
        };
    }
}

module.exports = SigmaProver;