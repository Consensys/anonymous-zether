const ABICoder = require('web3-eth-abi');
const BN = require('bn.js');

const bn128 = require('../utils/bn128.js');
const utils = require('../utils/utils.js');
const { PedersenCommitment, ElGamal, PedersenVectorCommitment, FieldVector } = require('../utils/algebra.js');
const { FieldVectorPolynomial } = require('../utils/misc.js');
const InnerProductProof = require('./innerproduct.js');

class BurnProof {
    constructor() {
        this.serialize = () => { // please initialize this before calling this method...
            let result = "0x";
            result += bn128.representation(this.BA.point()).slice(2);
            result += bn128.representation(this.BS.point()).slice(2);

            result += bn128.representation(this.T_1.point()).slice(2);
            result += bn128.representation(this.T_2.point()).slice(2);
            result += bn128.bytes(this.tHat).slice(2);
            result += bn128.bytes(this.mu).slice(2);

            result += bn128.bytes(this.c).slice(2);
            result += bn128.bytes(this.s_sk).slice(2);
            result += bn128.bytes(this.s_b).slice(2);
            result += bn128.bytes(this.s_tau).slice(2);

            result += this.ipProof.serialize().slice(2);

            return result;
        }
    }
    static prove(statement, witness) {
        const result = new BurnProof();

        const statementHash = utils.hash(ABICoder.encodeParameters([
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
            'uint256',
            'address',
        ], [
            bn128.serialize(statement['Cn'].left()),
            bn128.serialize(statement['Cn'].right()),
            bn128.serialize(statement['y']),
            statement['epoch'],
            statement['sender'],
        ])); // useless to break this out up top. "psychologically" easier

        witness['bDiff'] = new BN(witness['bDiff']).toRed(bn128.q);

        const aL = new FieldVector(witness['bDiff'].toString(2, 32).split("").reverse().map((i) => new BN(i, 2).toRed(bn128.q)));
        const aR = aL.plus(new BN(1).toRed(bn128.q).redNeg());
        result.BA = PedersenVectorCommitment.commit(aL, aR);
        const sL = new FieldVector(Array.from({ length: 32 }).map(bn128.randomScalar));
        const sR = new FieldVector(Array.from({ length: 32 }).map(bn128.randomScalar));
        result.BS = PedersenVectorCommitment.commit(sL, sR);

        const y = utils.hash(ABICoder.encodeParameters([
            'bytes32',
            'bytes32[2]',
            'bytes32[2]',
        ], [
            bn128.bytes(statementHash),
            bn128.serialize(result.BA.point()),
            bn128.serialize(result.BS.point()),
        ]));

        const ys = new FieldVector([new BN(1).toRed(bn128.q)]);
        for (let i = 1; i < 32; i++) { // it would be nice to have a nifty functional way of doing this.
            ys.push(ys.getVector()[i - 1].redMul(y));
        }
        const z = utils.hash(bn128.bytes(y));
        const zs = [z.redPow(new BN(2))];
        const twos = []
        for (let i = 0; i < 32; i++) twos[i] = new BN(1).shln(i).toRed(bn128.q);
        const twoTimesZs = new FieldVector(twos).times(zs[0]);

        const lPoly = new FieldVectorPolynomial(aL.plus(z.redNeg()), sL);
        const rPoly = new FieldVectorPolynomial(ys.hadamard(aR.plus(z)).add(twoTimesZs), sR.hadamard(ys));
        const tPolyCoefficients = lPoly.innerProduct(rPoly); // just an array of BN Reds... should be length 3
        result.T_1 = PedersenCommitment.commit(tPolyCoefficients[1]);
        result.T_2 = PedersenCommitment.commit(tPolyCoefficients[2]);

        const x = utils.hash(ABICoder.encodeParameters([
            'bytes32',
            'bytes32[2]',
            'bytes32[2]',
        ], [
            bn128.bytes(z),
            bn128.serialize(result.T_1.point()),
            bn128.serialize(result.T_2.point()),
        ]));

        result.tHat = tPolyCoefficients[0].redAdd(tPolyCoefficients[1].redMul(x)).redAdd(tPolyCoefficients[2].redMul(x.redPow(new BN(2))));
        const tauX = result.T_1.randomness.redMul(x).redAdd(result.T_2.randomness.redMul(x.redPow(new BN(2))));
        result.mu = result.BA.randomness.redAdd(result.BS.randomness.redMul(x));

        const k_sk = bn128.randomScalar();
        const k_b = bn128.randomScalar();
        const k_tau = bn128.randomScalar();

        const A_y = bn128.curve.g.mul(k_sk);
        const A_b = ElGamal.base['g'].mul(k_b).add(statement['Cn'].right().mul(zs[0]).mul(k_sk)); // wasted exponentiation
        const A_t = ElGamal.base['g'].mul(k_b.redNeg()).add(PedersenCommitment.base['h'].mul(k_tau));
        const A_u = utils.gEpoch(statement['epoch']).mul(k_sk);

        result.c = utils.hash(ABICoder.encodeParameters([
            'bytes32',
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
        ], [
            bn128.bytes(x),
            bn128.serialize(A_y),
            bn128.serialize(A_b),
            bn128.serialize(A_t),
            bn128.serialize(A_u),
        ]));

        result.s_sk = k_sk.redAdd(result.c.redMul(witness['sk']));
        result.s_b = k_b.redAdd(result.c.redMul(witness['bDiff'].redMul(zs[0])));
        result.s_tau = k_tau.redAdd(result.c.redMul(tauX));

        const hOld = PedersenVectorCommitment.base['h'];
        const gsOld = PedersenVectorCommitment.base['gs']; // horrible hack, but works.
        const hsOld = PedersenVectorCommitment.base['hs'];

        const o = utils.hash(ABICoder.encodeParameters([
            'bytes32',
        ], [
            bn128.bytes(result.c),
        ]));
        PedersenVectorCommitment.base['h'] = PedersenVectorCommitment.base['h'].mul(o);
        PedersenVectorCommitment.base['gs'] = PedersenVectorCommitment.base['gs'].slice(0, 32);
        PedersenVectorCommitment.base['hs'] = PedersenVectorCommitment.base['hs'].slice(0, 32).hadamard(ys.invert());

        const P = new PedersenVectorCommitment(bn128.zero); // P.decommit(lPoly.evaluate(x), rPoly.evaluate(x), result.tHat);
        P.gValues = lPoly.evaluate(x);
        P.hValues = rPoly.evaluate(x);
        P.randomness = result.tHat;
        result.ipProof = InnerProductProof.prove(P, o);

        PedersenVectorCommitment.base['h'] = hOld;
        PedersenVectorCommitment.base['gs'] = gsOld;
        PedersenVectorCommitment.base['hs'] = hsOld;
        return result;
    }
}

module.exports = BurnProof;