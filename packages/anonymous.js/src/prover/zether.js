const { AbiCoder } = require('web3-eth-abi');
const { soliditySha3 } = require('web3-utils');

const bn128 = require('../utils/bn128.js');
const GeneratorParams = require('../utils/params.js');

class ZetherProver {
    constructor() {
        var params = new GeneratorParams(64);
        var abiCoder = new AbiCoder();

        this.generateProof = (statement, witness) => {
            var number = witness['bTransfer'].add(witness['bDiff'].shln(32));
            var aL = number.toString(2).padStart(64, '0').split("").map((i) => new BN(i, 10));
            var aR = aL.map((i) => new BN(1).sub(i));
            var alpha = bn128.randomScalar();
            var a = params.commit(aL, aR, alpha);
            var sL = Array.from({ length: 64 }).map(bn128.randomScalar);
            var sR = Array.from({ length: 64 }).map(bn128.randomScalar);

            var rho = bn128.randomScalar(); // already reduced
            var s = params.commit(sL, sR, rho);

            var statementHash = soliditySha3(abiCoder.encodeParameters(['uint256', 'bytes32[2]', 'bytes32[2][]', 'bytes32[2][]', 'bytes32[2][]', 'bytes32[2][]'], [statement['epoch'], statement['R'], statement['CLn'], statement['CRn'], statement['L'], statement['y']]));
            var y = new BN(soliditySha3(statementHash, bn128.canonicalRepresentation(a), bn128.canonicalRepresentation(s)).slice(2), 16).toRed(bn128.groupReduction);
            var ys = [new BN(1).toRed(bn128.groupReduction)];
            for (var i = 1; i < 64; i++) { // it would be nice to have a nifty functional way of doing this.
                ys[i] = ys[i - 1].redMul(y);
            }
            var z = new BN(soliditySha("0x" + y.toString(16))).toRed(bn128.groupReduction);
            var zs = [z.redPow(new BN(2)), z.redPow(new BN(3))];
        }
    }
}

module.exports = ZetherProver;