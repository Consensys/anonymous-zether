const ABICoder = require('web3-eth-abi');
const BN = require('bn.js');

const bn128 = require('../utils/bn128.js');
const utils = require('../utils/utils.js');
const { PedersenCommitment, ElGamal, PedersenVectorCommitment, FieldVector, PointVector, ElGamalVector } = require('../utils/algebra.js');
const { Convolver, FieldVectorPolynomial, Polynomial } = require('../utils/misc.js');
const InnerProductProof = require('./innerproduct.js');

class ZetherProof {
    constructor() {
        this.serialize = () => { // please initialize this before calling this method...
            let result = "0x";
            result += bn128.representation(this.BA.point()).slice(2);
            result += bn128.representation(this.BS.point()).slice(2);
            result += bn128.representation(this.A.point()).slice(2);
            result += bn128.representation(this.B.point()).slice(2);

            this.CnG.forEach((CnG_k) => { result += bn128.representation(CnG_k.left()).slice(2); });
            this.CnG.forEach((CnG_k) => { result += bn128.representation(CnG_k.right()).slice(2); });
            this.C_0G.forEach((C_0G_k) => { result += bn128.representation(C_0G_k.left()).slice(2); });
            this.C_0G.forEach((C_0G_k) => { result += bn128.representation(C_0G_k.right()).slice(2); });
            this.y_0G.forEach((y_0G_k) => { result += bn128.representation(y_0G_k.left()).slice(2); });
            this.y_0G.forEach((y_0G_k) => { result += bn128.representation(y_0G_k.right()).slice(2); });
            this.C_XG.forEach((C_XG_k) => { result += bn128.representation(C_XG_k.left()).slice(2); });
            this.C_XG.forEach((C_XG_k) => { result += bn128.representation(C_XG_k.right()).slice(2); });
            this.f.getVector().forEach((f_k) => { result += bn128.bytes(f_k).slice(2); });

            result += bn128.bytes(this.z_A).slice(2);

            result += bn128.representation(this.T_1.point()).slice(2);
            result += bn128.representation(this.T_2.point()).slice(2);
            result += bn128.bytes(this.tHat).slice(2);
            result += bn128.bytes(this.mu).slice(2);

            result += bn128.bytes(this.c).slice(2);
            result += bn128.bytes(this.s_sk).slice(2);
            result += bn128.bytes(this.s_r).slice(2);
            result += bn128.bytes(this.s_b).slice(2);
            result += bn128.bytes(this.s_tau).slice(2);

            result += this.ipProof.serialize().slice(2);

            return result;
        };
    }

    static prove(statement, witness, fee) {
        const result = new ZetherProof();

        const statementHash = utils.hash(ABICoder.encodeParameters([
            'bytes32[2][]',
            'bytes32[2][]',
            'bytes32[2][]',
            'bytes32[2]',
            'bytes32[2][]',
            'uint256',
        ], [
            statement['Cn'].map((Cn_i) => bn128.serialize(Cn_i.left())),
            statement['Cn'].map((Cn_i) => bn128.serialize(Cn_i.right())),
            statement['C'].map((C_i) => bn128.serialize(C_i.left())),
            bn128.serialize(statement['C'][0].right()),
            statement['y'].map((key) => bn128.serialize(key)),
            statement['epoch'],
        ]));

        statement['Cn'] = new ElGamalVector(statement['Cn']);
        // statement['C'] = new ElGamalVector(statement['C']);
        statement['y'] = new PointVector(statement['y']);
        witness['bTransfer'] = new BN(witness['bTransfer']).toRed(bn128.q);
        witness['bDiff'] = new BN(witness['bDiff']).toRed(bn128.q);

        const index = witness['index'];
        const key = statement['y'].getVector()[index[0]];
        const number = witness['bTransfer'].add(witness['bDiff'].shln(32)); // shln a red? check
        const decomposition = number.toString(2, 64).split("").reverse();
        const aL = new FieldVector(Array.from({ 'length': 64 }).map((_, i) => new BN(decomposition[i], 2).toRed(bn128.q)));
        const aR = aL.plus(new BN(1).toRed(bn128.q).redNeg())
        result.BA = PedersenVectorCommitment.commit(aL, aR);
        const sL = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
        const sR = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
        result.BS = PedersenVectorCommitment.commit(sL, sR);

        const N = statement['y'].length();
        if (N & (N - 1)) throw "Size must be a power of 2!"; // probably unnecessary... this won't be called directly.
        const m = new BN(N).bitLength() - 1; // assuming that N is a power of 2?
        const a = new FieldVector(Array.from({ 'length': 2 * m }).map(bn128.randomScalar));
        const b = new FieldVector((new BN(witness['index'][1]).toString(2, m) + new BN(index[0]).toString(2, m)).split("").reverse().map((i) => new BN(i, 2).toRed(bn128.q)));
        const c = a.hadamard(b.times(new BN(2).toRed(bn128.q)).negate().plus(new BN(1).toRed(bn128.q)));
        const d = a.hadamard(a).negate();
        const e = new FieldVector([a.getVector()[0].redMul(a.getVector()[m]), a.getVector()[0].redMul(a.getVector()[m])]);
        const f = new FieldVector([a.getVector()[b.getVector()[0].toNumber() * m], a.getVector()[b.getVector()[m].toNumber() * m].redNeg()]);
        result.A = PedersenVectorCommitment.commit(a, d.concat(e)); // warning: semantic change for contract
        result.B = PedersenVectorCommitment.commit(b, c.concat(f)); // warning: semantic change for contract

        const v = utils.hash(ABICoder.encodeParameters([
            'bytes32',
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
        ], [
            bn128.bytes(statementHash),
            bn128.serialize(result.BA.point()),
            bn128.serialize(result.BS.point()),
            bn128.serialize(result.A.point()),
            bn128.serialize(result.B.point()),
        ]));

        const recursivePolynomials = (list, a, b) => {
            if (a.length === 0) return list;
            const aTop = a.pop();
            const bTop = b.pop();
            const left = new Polynomial([aTop.redNeg(), new BN(1).toRed(bn128.q).redSub(bTop)]); // X - f_k(X)
            const right = new Polynomial([aTop, bTop]); // f_k(X)
            for (let i = 0; i < list.length; i++) list[i] = [list[i].mul(left), list[i].mul(right)];
            return recursivePolynomials(list.flat(), a, b);
        }
        let P_poly = recursivePolynomials([new Polynomial([new BN(1).toRed(bn128.q)])], a.getVector().slice(0, m), b.getVector().slice(0, m));
        let Q_poly = recursivePolynomials([new Polynomial([new BN(1).toRed(bn128.q)])], a.getVector().slice(m), b.getVector().slice(m));
        P_poly = Array.from({ length: m }).map((_, k) => new FieldVector(P_poly.map((P_i) => P_i.coefficients[k])));
        Q_poly = Array.from({ length: m }).map((_, k) => new FieldVector(Q_poly.map((Q_i) => Q_i.coefficients[k])));

        const Phi = Array.from({ length: m }).map(() => ElGamal.commit(key, new BN(0).toRed(bn128.q)));
        const Chi = Array.from({ length: m }).map(() => ElGamal.commit(key, new BN(0).toRed(bn128.q)));
        const Psi = Array.from({ length: m }).map(() => ElGamal.commit(key, new BN(0).toRed(bn128.q)));

        result.CnG = Array.from({ length: m }).map((_, k) => statement['Cn'].multiExponentiate(P_poly[k]).add(Phi[k]));
        result.C_0G = Array.from({ length: m }).map((_, k) => {
            const left = new PointVector(statement['C'].map((C_i) => C_i.left())).multiExponentiate(P_poly[k]).add(Chi[k].left());
            return new ElGamal(left, Chi[k].right());
        });
        result.y_0G = Array.from({ length: m }).map((_, k) => {
            const left = statement['y'].multiExponentiate(P_poly[k]).add(Psi[k].left());
            return new ElGamal(left, Psi[k].right());
        });
        result.C_XG = Array.from({ length: m }).map(() => ElGamal.commit(statement['C'][0].right(), new BN(0).toRed(bn128.q)));

        let vPow = new BN(1).toRed(bn128.q);
        for (let i = 0; i < N; i++) { // could turn this into a complicated reduce, but...
            const poly = i % 2 ? Q_poly : P_poly; // clunky, i know, etc. etc.
            result.C_XG = result.C_XG.map((C_XG_k, k) => C_XG_k.plus(vPow.redMul(witness['bTransfer'].redNeg().redSub(new BN(fee).toRed(bn128.q)).redMul(poly[k].getVector()[(witness['index'][0] + N - (i - i % 2)) % N]).redAdd(witness['bTransfer'].redMul(poly[k].getVector()[(witness['index'][1] + N - (i - i % 2)) % N])))));
            if (i !== 0)
                vPow = vPow.redMul(v);
        }

        const w = utils.hash(ABICoder.encodeParameters([
            'bytes32',
            'bytes32[2][]',
            'bytes32[2][]',
            'bytes32[2][]',
            'bytes32[2][]',
            'bytes32[2][]',
            'bytes32[2][]',
            'bytes32[2][]',
            'bytes32[2][]',
        ], [
            bn128.bytes(v),
            result.CnG.map((CnG_k) => bn128.serialize(CnG_k.left())),
            result.CnG.map((CnG_k) => bn128.serialize(CnG_k.right())),
            result.C_0G.map((C_0G_k) => bn128.serialize(C_0G_k.left())),
            result.C_0G.map((C_0G_k) => bn128.serialize(C_0G_k.right())),
            result.y_0G.map((y_0G_k) => bn128.serialize(y_0G_k.left())),
            result.y_0G.map((y_0G_k) => bn128.serialize(y_0G_k.right())),
            result.C_XG.map((C_XG_k) => bn128.serialize(C_XG_k.left())),
            result.C_XG.map((C_XG_k) => bn128.serialize(C_XG_k.right())),
        ]));

        result.f = b.times(w).add(a);
        result.z_A = result.B.randomness.redMul(w).redAdd(result.A.randomness);

        const y = utils.hash(ABICoder.encodeParameters([
            'bytes32',
        ], [
            bn128.bytes(w), // that's it?
        ]));

        const ys = new FieldVector([new BN(1).toRed(bn128.q)]);
        for (let i = 1; i < 64; i++) { // it would be nice to have a nifty functional way of doing this.
            ys.push(ys.getVector()[i - 1].redMul(y));
        }
        const z = utils.hash(bn128.bytes(y));
        const zs = [z.redPow(new BN(2)), z.redPow(new BN(3))];
        const twos = []
        for (let i = 0; i < 32; i++) twos[i] = new BN(1).shln(i).toRed(bn128.q);
        const twoTimesZs = new FieldVector([]);
        for (let i = 0; i < 2; i++) {
            for (let j = 0; j < 32; j++) {
                twoTimesZs.push(zs[i].redMul(twos[j]));
            }
        }

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

        let CnR = new ElGamal(undefined, bn128.zero); // only need the RHS. this will give us CRnR
        let chi = new BN(0).toRed(bn128.q); // for DR
        let psi = new BN(0).toRed(bn128.q); // for gR
        let C_XR = new ElGamal(undefined, bn128.zero); // only need the RHS
        let p = new FieldVector(Array.from({ length: N }).map(() => new BN(0).toRed(bn128.q))); // evaluations of poly_0 and poly_1 at w.
        let q = new FieldVector(Array.from({ length: N }).map(() => new BN(0).toRed(bn128.q))); // verifier will compute these using f.

        let wPow = new BN(1).toRed(bn128.q);
        for (let k = 0; k < m; k++) {
            CnR = CnR.add(Phi[k].neg().mul(wPow));
            chi = chi.redAdd(Chi[k].randomness.redMul(wPow));
            psi = psi.redAdd(Psi[k].randomness.redMul(wPow));
            C_XR = C_XR.add(result.C_XG[k].neg().mul(wPow));
            p = p.add(P_poly[k].times(wPow));
            q = q.add(Q_poly[k].times(wPow));
            wPow = wPow.redMul(w);
        }
        CnR = CnR.add(statement['Cn'].getVector()[index[0]].mul(wPow));
        const DR = statement['C'][0].right().mul(wPow).add(bn128.curve.g.mul(chi.redNeg()));
        const gR = bn128.curve.g.mul(wPow.redSub(psi));
        p = p.add(new FieldVector(Array.from({ length: N }).map((_, i) => i === index[0] ? wPow : new BN().toRed(bn128.q))));
        q = q.add(new FieldVector(Array.from({ length: N }).map((_, i) => i === index[1] ? wPow : new BN().toRed(bn128.q))));

        const convolver = new Convolver();
        convolver.prepare(statement['y']);
        const y_p = convolver.convolution(p);
        const y_q = convolver.convolution(q);
        vPow = new BN(1).toRed(bn128.q);
        for (let i = 0; i < N; i++) {
            const y_poly = i % 2 ? y_q : y_p; // this is weird. stumped.
            C_XR = C_XR.add(new ElGamal(undefined, y_poly.getVector()[Math.floor(i / 2)].mul(vPow)));
            if (i > 0)
                vPow = vPow.redMul(v);
        }

        const k_sk = bn128.randomScalar();
        const k_r = bn128.randomScalar();
        const k_b = bn128.randomScalar();
        const k_tau = bn128.randomScalar();

        const A_y = gR.mul(k_sk);
        const A_D = bn128.curve.g.mul(k_r);
        const A_b = ElGamal.base['g'].mul(k_b).add(DR.mul(zs[0].redNeg()).add(CnR.right().mul(zs[1])).mul(k_sk));
        const A_X = C_XR.right().mul(k_r); // y_XR.mul(k_r);
        const A_t = ElGamal.base['g'].mul(k_b.redNeg()).add(PedersenCommitment.base['h'].mul(k_tau));
        const A_u = utils.gEpoch(statement['epoch']).mul(k_sk);

        result.c = utils.hash(ABICoder.encodeParameters([
            'bytes32',
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
            'bytes32[2]',
        ], [
            bn128.bytes(x),
            bn128.serialize(A_y),
            bn128.serialize(A_D),
            bn128.serialize(A_b),
            bn128.serialize(A_X),
            bn128.serialize(A_t),
            bn128.serialize(A_u),
        ]));

        result.s_sk = k_sk.redAdd(result.c.redMul(witness['sk']));
        result.s_r = k_r.redAdd(result.c.redMul(witness['r']));
        result.s_b = k_b.redAdd(result.c.redMul(witness['bTransfer'].redMul(zs[0]).redAdd(witness['bDiff'].redMul(zs[1])).redMul(wPow)));
        result.s_tau = k_tau.redAdd(result.c.redMul(tauX.redMul(wPow)));

        const hOld = PedersenVectorCommitment.base['h'];
        const hsOld = PedersenVectorCommitment.base['hs'];
        const o = utils.hash(ABICoder.encodeParameters([
            'bytes32',
        ], [
            bn128.bytes(result.c),
        ]));
        PedersenVectorCommitment.base['h'] = PedersenVectorCommitment.base['h'].mul(o);
        PedersenVectorCommitment.base['hs'] = PedersenVectorCommitment.base['hs'].hadamard(ys.invert());

        const P = new PedersenVectorCommitment(bn128.zero); // P._commit(lPoly.evaluate(x), rPoly.evaluate(x), result.tHat);
        P.gValues = lPoly.evaluate(x);
        P.hValues = rPoly.evaluate(x);
        P.randomness = result.tHat;
        result.ipProof = InnerProductProof.prove(P, o);

        PedersenVectorCommitment.base['h'] = hOld;
        PedersenVectorCommitment.base['hs'] = hsOld;
        return result;
    }
}

module.exports = ZetherProof;