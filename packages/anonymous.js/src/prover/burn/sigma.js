const { AbiCoder } = require('web3-eth-abi');

const { GeneratorParams, FieldVector } = require('../algebra.js');
const bn128 = require('../../utils/bn128.js');

class SigmaProof {
    constructor() {
        this.serialize = () => {
            var result = "0x";
            result += bn128.bytes(this.challenge).slice(2);
            result += bn128.bytes(this.sX).slice(2);
            return result;
        };
    }
}

class SigmaProver {
    constructor() {
        var abiCoder = new AbiCoder();

        this.generateProof = (statement, witness, salt) => {
            var y = statement['y'];
            var z = statement['z'];
            var zSquared = z.redMul(statement['z']);

            var kR = bn128.randomScalar();
            var kX = bn128.randomScalar();

            var Ay = statement['gPrime'].mul(kX);
            var Au = utils.gEpoch(statement['epoch']).mul(kX);
            var ADiff = y.add(yBar).mul(kR);
            var At = statement['CRn'].mul(zSquared).mul(kX);

            var proof = new SigmaProof();

            proof.challenge = utils.hash(abiCoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
            ], [
                bn128.bytes(salt),
                bn128.serialize(Ay),
                bn128.serialize(Au),
                bn128.serialize(At)
            ]));

            proof.sX = kX.redAdd(proof['challenge'].redMul(witness['x']));

            return proof;
        };
    }
}

module.exports = SigmaProver;