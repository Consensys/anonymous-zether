const { AbiCoder } = require('web3-eth-abi');

const bn128 = require('../../utils/bn128.js');
const { GeneratorParams, FieldVector, FieldVectorPolynomial, PolyCommitment } = require('algebra.js');

class ZetherProver {
    constructor() {
        var params = new GeneratorParams(64);
        var abiCoder = new AbiCoder();

        this.generateProof = (statement, witness, salt) => { // salt probably won't be used
            var number = witness['bTransfer'].add(witness['bDiff'].shln(32));
            var aL = new FieldVector(number.toString(2, 64).split("").map((i) => new BN(i, 2).toRed(bn128.q)));
            var aR = new FieldVector(aL.map((i) => new BN(1).toRed(bn128.q).redSub(i)));
            var alpha = bn128.randomScalar();
            var a = params.commit(aL, aR, alpha);
            var sL = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
            var sR = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));

            var rho = bn128.randomScalar(); // already reduced
            var s = params.commit(sL, sR, rho);

            var statementHash = utils.hash(abiCoder.encodeParameters(['uint256', 'bytes32[2]', 'bytes32[2][]', 'bytes32[2][]', 'bytes32[2][]', 'bytes32[2][]'], [statement['epoch'], statement['R'], statement['CLn'], statement['CRn'], statement['L'], statement['y']]));
            var y = utils.hash(bn128.bytes(statementHash), bn128.serialize(a), bn128.serialize(s));
            var ys = [new BN(1).toRed(bn128.q)];
            for (var i = 1; i < 64; i++) { // it would be nice to have a nifty functional way of doing this.
                ys.push(ys[i - 1].redMul(y));
            }
            ys = new FieldVector(ys); // could avoid this line by starting ys as a fieldvector and using "plus". not going to bother.
            var z = utils.hash(bn128.bytes(y));
            var zs = [z.redPow(new BN(2)), z.redPow(new BN(3))];
            var twos = [new BN(1).toRed(bn128.q)];
            for (var i = 1; i < 32; i++) {
                twos.push(twos[i - 1].redMul(new BN(2).toRed(bn128.q)));
            }
            var twoTimesZs = [];
            for (var i = 0; i < 2; i++) {
                for (var j = 0; j < 32; j++) {
                    twoTimesZs.push(zs[i].redMul(twos[j]));
                }
            }
            twoTimesZs = new FieldVector(twoTimesZs);
            var l0 = aL.plus(z.neg());
            var l1 = sL;
            var lPoly = new FieldVectorPolynomial(l0, l1);
            var r0 = ys.hadamard(aR.plus(z)).add(twoTimesZs);
            var r1 = sR.hadamard(ys);
            var rPoly = new FieldVectorPolynomial(r0, r1);
            var tPolyCoefficients = lPoly.innerProduct(rPoly); // just an array of BN Reds... should be length 3
            var polyCommitment = new PolyCommitment(params, tPolyCoefficients);
            var x = utils.hash(bn128.bytes(z), ...polyCommitment.getCommitments());
            var evalCommit = polyCommitment.evaluate(x);
            var t = evalCommit.getX();
            var mu = alpha.redAdd(rho.redMul(x));

            var size = statement['y'].length;
            var anonProver = new AnonProver();
            var anonWitness = { 'index': witness['index'], 'pi': bn128.randomScalar(), 'rho': bn128.randomScalar(), 'sigma': bn128.randomScalar() };
            var anonProof = anonProver.generateProof(statement, anonWitness, x);

            var challenge = anonProof['challenge'];
        }
    }
}

module.exports = ZetherProver;