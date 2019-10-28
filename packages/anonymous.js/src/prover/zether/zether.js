const { AbiCoder } = require('web3-eth-abi');
const BN = require('bn.js');

const bn128 = require('../../utils/bn128.js');
const utils = require('../../utils/utils.js');
const { GeneratorParams, GeneratorVector, FieldVector, FieldVectorPolynomial, PolyCommitment } = require('../algebra.js');
const AnonProver = require('./anon.js');
const SigmaProver = require('./sigma.js');
const InnerProductProver = require('../innerproduct.js');

class ZetherProof {
    constructor() {
        this.serialize = () => { // please initialize this before calling this method...
            var result = "0x";
            result += bn128.representation(this.a).slice(2);
            result += bn128.representation(this.s).slice(2);
            result += bn128.representation(this.HL).slice(2);
            result += bn128.representation(this.HR).slice(2);
            this.tCommits.getVector().forEach((commit) => {
                result += bn128.representation(commit).slice(2);
            });
            result += bn128.bytes(this.t).slice(2);
            result += bn128.bytes(this.tauX).slice(2);
            result += bn128.bytes(this.mu).slice(2);
            result += this.sigmaProof.serialize().slice(2);
            result += this.ipProof.serialize().slice(2);
            result += this.anonProof.serialize().slice(2);
            return result;
        }
    };
}

class ZetherProver {
    constructor() {
        var abiCoder = new AbiCoder();

        var params = new GeneratorParams();
        params.extend(64);

        var anonProver = new AnonProver();
        var sigmaProver = new SigmaProver();
        var ipProver = new InnerProductProver();

        this.generateProof = (statement, witness, salt) => { // salt probably won't be used
            var proof = new ZetherProof();

            var statementHash = utils.hash(abiCoder.encodeParameters(['bytes32[2][]', 'bytes32[2][]', 'bytes32[2][]', 'bytes32[2]', 'bytes32[2][]', 'uint256'], [statement['CLn'], statement['CRn'], statement['C'], statement['D'], statement['y'], statement['epoch']]));
            statement['CLn'] = new GeneratorVector(statement['CLn'].map(bn128.unserialize));
            statement['CRn'] = new GeneratorVector(statement['CRn'].map(bn128.unserialize));
            statement['C'] = new GeneratorVector(statement['C'].map(bn128.unserialize));
            statement['D'] = bn128.unserialize(statement['D']);
            statement['y'] = new GeneratorVector(statement['y'].map(bn128.unserialize));
            // go ahead and "liven" these once and for all now that they have been hashed

            var number = new BN(witness['bTransfer']).add(new BN(witness['bDiff']).shln(32));
            var aL = new FieldVector(number.toString(2, 64).split("").reverse().map((i) => new BN(i, 2).toRed(bn128.q)));
            var aR = aL.plus(new BN(1).toRed(bn128.q).redNeg());
            var alpha = bn128.randomScalar();
            proof.a = params.commit(aL, aR, alpha);
            var sL = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
            var sR = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
            var rho = bn128.randomScalar(); // already reduced
            proof.s = params.commit(sL, sR, rho);
            var gamma = bn128.randomScalar();
            var rGamma = bn128.randomScalar();
            proof.HL = params.getH().mul(gamma).add(statement['y'].getVector()[witness['index'][0]].mul(rGamma));
            proof.HR = params.getG().mul(rGamma); // (HL, HR) is an ElGamal encryption of h^gamma under y...

            var y = utils.hash(abiCoder.encodeParameters(['bytes32', 'bytes32[2]', 'bytes32[2]', 'bytes32[2]', 'bytes32[2]'], [bn128.bytes(statementHash), bn128.serialize(proof.a), bn128.serialize(proof.s), bn128.serialize(proof.HL), bn128.serialize(proof.HR)]));
            var ys = [new BN(1).toRed(bn128.q)];
            for (var i = 1; i < 64; i++) { // it would be nice to have a nifty functional way of doing this.
                ys.push(ys[i - 1].redMul(y));
            }
            ys = new FieldVector(ys); // could avoid this line by starting ys as a fieldvector and using "plus". not going to bother.
            var z = utils.hash(bn128.bytes(y));
            var zs = [z.redPow(new BN(2))];
            for (var i = 1; i < 3; i++) {
                zs.push(zs[i - 1].redMul(z));
            }
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
            var l0 = aL.plus(z.redNeg());
            var l1 = sL;
            var lPoly = new FieldVectorPolynomial(l0, l1);
            var r0 = ys.hadamard(aR.plus(z)).add(twoTimesZs);
            var r1 = sR.hadamard(ys);
            var rPoly = new FieldVectorPolynomial(r0, r1);
            var tPolyCoefficients = lPoly.innerProduct(rPoly); // just an array of BN Reds... should be length 3
            var polyCommitment = new PolyCommitment(params, tPolyCoefficients, zs[2].redMul(gamma));
            var x = utils.hash(abiCoder.encodeParameters(['bytes32', 'bytes32[2]', 'bytes32[2]'], [bn128.bytes(z), ...polyCommitment.getCommitments().map(bn128.serialize)]));
            var evalCommit = polyCommitment.evaluate(x);
            proof.tCommits = new GeneratorVector(polyCommitment.getCommitments()); // just 2 of them?
            proof.t = evalCommit.getX();
            proof.tauX = evalCommit.getR();
            proof.mu = alpha.redAdd(rho.redMul(x));

            var anonWitness = {}; // could just pass in the entire zether witness...?
            anonWitness['index'] = witness['index'];
            anonWitness['bDiff'] = witness['bDiff'];
            anonWitness['r'] = witness['r'];
            anonWitness['sigma'] = bn128.randomScalar();
            proof.anonProof = anonProver.generateProof(statement, anonWitness, x);

            var challenge = proof.anonProof.challenge;

            var sigmaStatement = {}; // only certain parts of the "statement" are actually used in proving.
            sigmaStatement['CRn'] = statement['CRn'].getVector()[witness['index'][0]].mul(challenge.redSub(anonWitness['sigma']));
            sigmaStatement['y'] = Array.from({ length: 2 }).map((_, i) => statement['y'].shift(witness['index'][i]).extract(0).times(challenge.redSub(anonWitness['sigma'])));
            sigmaStatement['D'] = statement['D'].mul(challenge.redSub(anonWitness['sigma']));
            sigmaStatement['gG'] = params.getG().mul(challenge.redSub(anonWitness['sigma']));
            sigmaStatement['z'] = z;
            sigmaStatement['epoch'] = statement['epoch'];
            sigmaStatement['HR'] = proof.HR;
            var sigmaWitness = {};
            sigmaWitness['x'] = witness['x'];
            sigmaWitness['r'] = witness['r'];
            sigmaWitness['w'] = challenge;
            proof.sigmaProof = sigmaProver.generateProof(sigmaStatement, sigmaWitness, challenge);

            var uChallenge = utils.hash(abiCoder.encodeParameters(['bytes32', 'bytes32', 'bytes32', 'bytes32'], [bn128.bytes(proof.sigmaProof.challenge), bn128.bytes(proof.t), bn128.bytes(proof.tauX), bn128.bytes(proof.mu)]));
            var u = params.getG().mul(uChallenge);
            var gs = params.getGs();
            var hPrimes = params.getHs().hadamard(ys.invert());
            var hExp = ys.times(z).add(twoTimesZs);
            var P = proof.a.add(proof.s.mul(x)).add(gs.sum().mul(z.redNeg())).add(hPrimes.commit(hExp)).add(u.mul(proof.t)).add(params.getH().mul(proof.mu).neg());
            var primeBase = new GeneratorParams(gs, hPrimes, u);
            var ipStatement = { 'primeBase': primeBase, 'P': P }; // "cheating" by including primeBase in the statement while in reality it's "params"
            var ipWitness = { 'l': lPoly.evaluate(x), 'r': rPoly.evaluate(x) };
            proof.ipProof = ipProver.generateProof(ipStatement, ipWitness, uChallenge);

            return proof;
        }
    }
}

module.exports = ZetherProver;