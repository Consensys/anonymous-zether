const { AbiCoder } = require('web3-eth-abi');
const { soliditySha3 } = require('web3-utils');
const BN = require('bn.js');

const { GeneratorParams, FieldVector } = require('../algebra.js');
const bn128 = require('../../utils/bn128.js');
const utils = require('../../utils/utils.js');

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

        var params = new GeneratorParams();

        this.generateProof = (statement, witness, salt) => {
            var z = statement['z'];
            var zs = [z.redPow(new BN(2))];
            for (var i = 1; i < 2; i++) {
                zs.push(zs[i - 1].redMul(z));
            }

            var kX = bn128.randomScalar();

            var Ay = params.getG().mul(kX);
            var Au = utils.gEpoch(statement['epoch']).mul(kX);
            var At = statement['CRn'].mul(zs[0]).add(statement['HR'].mul(zs[1])).mul(kX);

            var proof = new SigmaProof();

            proof.challenge = utils.hash(abiCoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'address',
            ], [
                bn128.bytes(salt),
                bn128.serialize(Ay),
                bn128.serialize(Au),
                bn128.serialize(At),
                statement.sender,
            ]));

            proof.sX = kX.redAdd(proof['challenge'].redMul(witness['x']));

            return proof;
        };
    }
}

module.exports = SigmaProver;