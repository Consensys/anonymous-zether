const { AbiCoder } = require('web3-eth-abi');
const BN = require('bn.js');

const bn128 = require('../utils/bn128.js');
const utils = require('../utils/utils.js');
const { GeneratorParams, GeneratorVector, FieldVector, FieldVectorPolynomial, PolyCommitment } = require('./algebra.js');
const InnerProductProver = require('./innerproduct.js');

class BurnProof {
    constructor() {
        this.serialize = () => { // please initialize this before calling this method...
            var result = "0x";
            result += bn128.representation(this.A).slice(2);
            result += bn128.representation(this.S).slice(2);

            result += bn128.representation(this.CLnPrime).slice(2);
            result += bn128.representation(this.CRnPrime).slice(2);

            this.tCommits.getVector().forEach((commit) => {
                result += bn128.representation(commit).slice(2);
            });
            result += bn128.bytes(this.tHat).slice(2);
            result += bn128.bytes(this.tauX).slice(2);
            result += bn128.bytes(this.mu).slice(2);

            result += bn128.bytes(this.c).slice(2);
            result += bn128.bytes(this.s_sk).slice(2);
            result += bn128.bytes(this.s_vDiff).slice(2);
            result += bn128.bytes(this.s_nuDiff).slice(2);

            result += this.ipProof.serialize().slice(2);

            return result;
        }
    };
}

class BurnProver {
    constructor() {
        var abiCoder = new AbiCoder();

        var params = new GeneratorParams();
        params.extend(32);
        var ipProver = new InnerProductProver();

        this.generateProof = (statement, witness) => { // salt probably won't be used
            var proof = new BurnProof();

            var statementHash = utils.hash(abiCoder.encodeParameters([
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'uint256',
                'uint256',
                'address',
            ], [
                statement['CLn'],
                statement['CRn'],
                statement['y'],
                statement['bTransfer'],
                statement['epoch'],
                statement['sender'],
            ])); // useless to break this out up top. "psychologically" easier

            statement['CLn'] = bn128.unserialize(statement['CLn']);
            statement['CRn'] = bn128.unserialize(statement['CRn']);
            statement['y'] = bn128.unserialize(statement['y']);
            witness['bDiff'] = new BN(witness['bDiff']).toRed(bn128.q);

            var aL = new FieldVector(witness['bDiff'].toString(2, 32).split("").reverse().map((i) => new BN(i, 2).toRed(bn128.q)));
            var aR = aL.plus(new BN(1).toRed(bn128.q).redNeg());
            var alpha = bn128.randomScalar();
            proof.A = params.commit(aL, aR, alpha);
            var sL = new FieldVector(Array.from({ length: 32 }).map(bn128.randomScalar));
            var sR = new FieldVector(Array.from({ length: 32 }).map(bn128.randomScalar));
            var rho = bn128.randomScalar(); // already reduced
            proof.S = params.commit(sL, sR, rho);

            var gammaDiff = bn128.randomScalar();
            var zetaDiff = bn128.randomScalar();
            proof.CLnPrime = params.getH().mul(gammaDiff).add(statement['y'].mul(zetaDiff));
            proof.CRnPrime = params.getG().mul(zetaDiff);

            var y = utils.hash(abiCoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
            ], [
                bn128.bytes(statementHash),
                bn128.serialize(proof.A),
                bn128.serialize(proof.S),
                bn128.serialize(proof.CLnPrime),
                bn128.serialize(proof.CRnPrime),
            ]));

            var ys = [new BN(1).toRed(bn128.q)];
            for (var i = 1; i < 32; i++) { // it would be nice to have a nifty functional way of doing this.
                ys.push(ys[i - 1].redMul(y));
            }
            ys = new FieldVector(ys); // could avoid this line by starting ys as a fieldvector and using "plus". not going to bother.
            var z = utils.hash(bn128.bytes(y));
            var zs = [z.redPow(new BN(2))];
            var twos = [new BN(1).toRed(bn128.q)];
            for (var i = 1; i < 32; i++) {
                twos.push(twos[i - 1].redMul(new BN(2).toRed(bn128.q)));
            }
            var twoTimesZs = new FieldVector(twos).times(zs[0]);
            var lPoly = new FieldVectorPolynomial(aL.plus(z.redNeg()), sL);
            var rPoly = new FieldVectorPolynomial(ys.hadamard(aR.plus(z)).add(twoTimesZs), sR.hadamard(ys));
            var tPolyCoefficients = lPoly.innerProduct(rPoly); // just an array of BN Reds... should be length 3
            var polyCommitment = new PolyCommitment(params, tPolyCoefficients, zs[0].redMul(gammaDiff));
            proof.tCommits = new GeneratorVector(polyCommitment.getCommitments()); // just 2 of them

            var x = utils.hash(abiCoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
            ], [
                bn128.bytes(z),
                ...polyCommitment.getCommitments().map(bn128.serialize),
            ]));

            var evalCommit = polyCommitment.evaluate(x);
            proof.tHat = evalCommit.getX();
            proof.tauX = evalCommit.getR();
            proof.mu = alpha.redAdd(rho.redMul(x));

            var k_sk = bn128.randomScalar();
            var k_vDiff = bn128.randomScalar(); // v "corresponds to" b
            var k_nuDiff = bn128.randomScalar(); // nu "corresponds to" gamma

            var A_y = params.getG().mul(k_sk);
            var A_u = utils.gEpoch(statement['epoch']).mul(k_sk);
            var A_t = statement['CRn'].add(proof.CRnPrime).mul(zs[0]).mul(k_sk);
            var A_CLn = params.getG().mul(k_vDiff).add(statement['CRn'].mul(k_sk));
            var A_CLnPrime = params.getH().mul(k_nuDiff).add(proof.CRnPrime.mul(k_sk));

            proof.c = utils.hash(abiCoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
            ], [
                bn128.bytes(x),
                bn128.serialize(A_y),
                bn128.serialize(A_u),
                bn128.serialize(A_t),
                bn128.serialize(A_CLn),
                bn128.serialize(A_CLnPrime),
            ]));

            proof.s_sk = k_sk.redAdd(proof.c.redMul(witness['sk']));
            proof.s_vDiff = k_vDiff.redAdd(proof.c.redMul(witness['bDiff']));
            proof.s_nuDiff = k_nuDiff.redAdd(proof.c.redMul(gammaDiff));

            var gs = params.getGs();
            var hsPrime = params.getHs().hadamard(ys.invert());
            var hExp = ys.times(z).add(twoTimesZs);
            var Z = proof.A.add(proof.S.mul(x)).add(gs.sum().mul(z.redNeg())).add(hsPrime.commit(hExp)); // rename of P
            Z = Z.add(params.getH().mul(proof.mu.redNeg())); // Statement P of protocol 1. should this be included in the calculation of v...?

            var o = utils.hash(abiCoder.encodeParameters([
                'bytes32',
            ], [
                bn128.bytes(proof.c),
            ]));

            var u_x = params.getG().mul(o); // Begin Protocol 1. this is u^x in Protocol 1. use our g for their u, our o for their x.
            var ZPrime = Z.add(u_x.mul(proof.tHat)); // corresponds to P' in protocol 1.
            var primeBase = new GeneratorParams(gs, hsPrime, u_x);
            var ipStatement = { 'primeBase': primeBase, 'P': ZPrime };
            var ipWitness = {};
            ipWitness['l'] = lPoly.evaluate(x);
            ipWitness['r'] = rPoly.evaluate(x);
            proof.ipProof = ipProver.generateProof(ipStatement, ipWitness, o);

            return proof;
        }
    }
}

module.exports = BurnProver;