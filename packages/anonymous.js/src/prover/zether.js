const ABICoder = require('web3-eth-abi');
const BN = require('bn.js');

const bn128 = require('../utils/bn128.js');
const utils = require('../utils/utils.js');
const { Convolver, FieldVector, FieldVectorPolynomial, GeneratorParams, GeneratorVector, PolyCommitment, Polynomial } = require('./algebra.js');
const InnerProductProver = require('./innerproduct.js');

class ZetherProof {
    constructor() {
        this.serialize = () => { // please initialize this before calling this method...
            var result = "0x";
            result += bn128.representation(this.BA).slice(2);
            result += bn128.representation(this.BS).slice(2);
            result += bn128.representation(this.A).slice(2);
            result += bn128.representation(this.B).slice(2);
            result += bn128.representation(this.C).slice(2);
            result += bn128.representation(this.D).slice(2);
            result += bn128.representation(this.E).slice(2);
            result += bn128.representation(this.F).slice(2);

            this.CLnG.forEach((CLnG_k) => { result += bn128.representation(CLnG_k).slice(2); });
            this.CRnG.forEach((CRnG_k) => { result += bn128.representation(CRnG_k).slice(2); });
            this.C_0G.forEach((C_0G_k) => { result += bn128.representation(C_0G_k).slice(2); });
            this.DG.forEach((DG_k) => { result += bn128.representation(DG_k).slice(2); });
            this.y_0G.forEach((y_0G_k) => { result += bn128.representation(y_0G_k).slice(2); });
            this.gG.forEach((gG_k) => { result += bn128.representation(gG_k).slice(2); });
            this.C_XG.forEach((C_XG_k) => { result += bn128.representation(C_XG_k).slice(2); });
            this.y_XG.forEach((y_XG_k) => { result += bn128.representation(y_XG_k).slice(2); });
            this.f.getVector().forEach((f_k) => { result += bn128.bytes(f_k).slice(2); });

            result += bn128.bytes(this.z_A).slice(2);
            result += bn128.bytes(this.z_C).slice(2);
            result += bn128.bytes(this.z_E).slice(2);

            result += bn128.representation(this.CPrime).slice(2);
            result += bn128.representation(this.DPrime).slice(2);
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
            result += bn128.bytes(this.s_r).slice(2);
            result += bn128.bytes(this.s_vTransfer).slice(2);
            result += bn128.bytes(this.s_vDiff).slice(2);
            result += bn128.bytes(this.s_nuTransfer).slice(2);
            result += bn128.bytes(this.s_nuDiff).slice(2);

            result += this.ipProof.serialize().slice(2);

            return result;
        }
    };
}

class ZetherProver {
    constructor() {
        var params = new GeneratorParams(64);
        var ipProver = new InnerProductProver();

        var recursivePolynomials = (list, accum, a, b) => {
            // as, bs are log(N)-lengthed.
            // returns N-length list of coefficient vectors
            // should take about N log N to compute.
            if (a.length == 0) {
                list.push(accum.coefficients);
                return;
            }
            var aTop = a.pop();
            var bTop = b.pop();
            var left = new Polynomial([aTop.redNeg(), new BN(1).toRed(bn128.q).redSub(bTop)]);
            var right = new Polynomial([aTop, bTop]);
            recursivePolynomials(list, accum.mul(left), a, b);
            recursivePolynomials(list, accum.mul(right), a, b);
            a.push(aTop);
            b.push(bTop);
        }

        this.generateProof = (statement, witness) => {
            var proof = new ZetherProof();

            var statementHash = utils.hash(ABICoder.encodeParameters([
                'bytes32[2][]',
                'bytes32[2][]',
                'bytes32[2][]',
                'bytes32[2]',
                'bytes32[2][]',
                'uint256',
            ], [
                statement['CLn'],
                statement['CRn'],
                statement['C'],
                statement['D'],
                statement['y'],
                statement['epoch'],
            ]));

            statement['CLn'] = new GeneratorVector(statement['CLn'].map(bn128.unserialize));
            statement['CRn'] = new GeneratorVector(statement['CRn'].map(bn128.unserialize));
            statement['C'] = new GeneratorVector(statement['C'].map(bn128.unserialize));
            statement['D'] = bn128.unserialize(statement['D']);
            statement['y'] = new GeneratorVector(statement['y'].map(bn128.unserialize));
            witness['bTransfer'] = new BN(witness['bTransfer']).toRed(bn128.q);
            witness['bDiff'] = new BN(witness['bDiff']).toRed(bn128.q);

            var number = witness['bTransfer'].add(witness['bDiff'].shln(32)); // shln a red? check
            var aL = new FieldVector(number.toString(2, 64).split("").reverse().map((i) => new BN(i, 2).toRed(bn128.q)));
            var aR = aL.plus(new BN(1).toRed(bn128.q).redNeg());
            var alpha = bn128.randomScalar();
            proof.BA = params.commit(alpha, aL, aR);
            var sL = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
            var sR = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
            var rho = bn128.randomScalar(); // already reduced
            proof.BS = params.commit(rho, sL, sR);

            var N = statement['y'].length();
            if (N & (N - 1))
                throw "Size must be a power of 2!"; // probably unnecessary... this won't be called directly.
            var m = new BN(N).bitLength() - 1; // assuming that N is a power of 2?
            // DON'T need to extend the params anymore. 64 will always be enough.
            var r_A = bn128.randomScalar();
            var r_B = bn128.randomScalar();
            var r_C = bn128.randomScalar();
            var r_D = bn128.randomScalar();
            var r_E = bn128.randomScalar();
            var r_F = bn128.randomScalar();
            var a = new FieldVector(Array.from({ length: 2 * m }).map(bn128.randomScalar));
            var b = new FieldVector((new BN(witness['index'][1]).toString(2, m) + new BN(witness['index'][0]).toString(2, m)).split("").reverse().map((i) => new BN(i, 2).toRed(bn128.q)));
            var c = a.hadamard(b.times(new BN(2).toRed(bn128.q)).negate().plus(new BN(1).toRed(bn128.q))); // check this
            var d = a.hadamard(a).negate();
            proof.A = params.commit(r_A, a);
            proof.B = params.commit(r_B, b);
            proof.C = params.commit(r_C, c);
            proof.D = params.commit(r_D, d);
            proof.E = params.commit(r_E, new FieldVector([a.getVector()[0].redMul(a.getVector()[m]), a.getVector()[0].redMul(a.getVector()[m])]));
            proof.F = params.commit(r_F, new FieldVector([a.getVector()[b.getVector()[0].toNumber() * m], a.getVector()[b.getVector()[m].toNumber() * m].redNeg()]));

            var v = utils.hash(ABICoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
            ], [
                bn128.bytes(statementHash),
                bn128.serialize(proof.BA),
                bn128.serialize(proof.BS),
                bn128.serialize(proof.A),
                bn128.serialize(proof.B),
                bn128.serialize(proof.C),
                bn128.serialize(proof.D),
                bn128.serialize(proof.E),
                bn128.serialize(proof.F),
            ]));

            var phi = Array.from({ length: m }).map(bn128.randomScalar);
            var chi = Array.from({ length: m }).map(bn128.randomScalar);
            var psi = Array.from({ length: m }).map(bn128.randomScalar);
            var omega = Array.from({ length: m }).map(bn128.randomScalar);

            var P = [];
            var Q = [];
            recursivePolynomials(P, new Polynomial(), a.getVector().slice(0, m), b.getVector().slice(0, m));
            recursivePolynomials(Q, new Polynomial(), a.getVector().slice(m), b.getVector().slice(m));
            P = Array.from({ length: m }).map((_, k) => new FieldVector(P.map((P_i) => P_i[k])));
            Q = Array.from({ length: m }).map((_, k) => new FieldVector(Q.map((Q_i) => Q_i[k])));

            proof.CLnG = Array.from({ length: m }).map((_, k) => statement['CLn'].commit(P[k]).add(statement['y'].getVector()[witness['index'][0]].mul(phi[k])));
            proof.CRnG = Array.from({ length: m }).map((_, k) => statement['CRn'].commit(P[k]).add(params.getG().mul(phi[k])));
            proof.C_0G = Array.from({ length: m }).map((_, k) => statement['C'].commit(P[k]).add(statement['y'].getVector()[witness['index'][0]].mul(chi[k])));
            proof.DG = Array.from({ length: m }).map((_, k) => params.getG().mul(chi[k]));
            proof.y_0G = Array.from({ length: m }).map((_, k) => statement['y'].commit(P[k]).add(statement['y'].getVector()[witness['index'][0]].mul(psi[k])));
            proof.gG = Array.from({ length: m }).map((_, k) => params.getG().mul(psi[k]));
            proof.C_XG = Array.from({ length: m }).map((_, k) => statement['D'].mul(omega[k]));
            proof.y_XG = Array.from({ length: m }).map((_, k) => params.getG().mul(omega[k]));
            var vPow = new BN(1).toRed(bn128.q);
            for (var i = 0; i < N; i++) { // could turn this into a complicated reduce, but...
                var temp = params.getG().mul(witness['bTransfer'].redMul(vPow));
                var poly = i % 2 ? Q : P; // clunky, i know, etc. etc.
                proof.C_XG = proof.C_XG.map((C_XG_k, k) => C_XG_k.add(temp.mul(poly[k].getVector()[(witness['index'][0] + N - (i - i % 2)) % N].redSub(poly[k].getVector()[(witness['index'][1] + N - (i - i % 2)) % N]))));
                if (i != 0)
                    vPow = vPow.redMul(v);
            }

            var w = utils.hash(ABICoder.encodeParameters([
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
                proof.CLnG.map(bn128.serialize),
                proof.CRnG.map(bn128.serialize),
                proof.C_0G.map(bn128.serialize),
                proof.DG.map(bn128.serialize),
                proof.y_0G.map(bn128.serialize),
                proof.gG.map(bn128.serialize),
                proof.C_XG.map(bn128.serialize),
                proof.y_XG.map(bn128.serialize),
            ]));

            proof.f = b.times(w).add(a);
            proof.z_A = r_B.redMul(w).redAdd(r_A);
            proof.z_C = r_C.redMul(w).redAdd(r_D);
            proof.z_E = r_F.redMul(w).redAdd(r_E);

            var CRnR = bn128.zero;
            var y_0R = bn128.zero;
            var y_XR = bn128.zero;
            var DR = bn128.zero;
            var gR = bn128.zero;
            var p = new FieldVector(Array.from({ length: N }).map(() => new BN().toRed(bn128.q))); // evaluations of poly_0 and poly_1 at w.
            var q = new FieldVector(Array.from({ length: N }).map(() => new BN().toRed(bn128.q))); // verifier will compute these using f.

            var wPow = new BN(1).toRed(bn128.q);
            for (var k = 0; k < m; k++) {
                CRnR = CRnR.add(params.getG().mul(phi[k].redNeg().redMul(wPow)));
                DR = DR.add(params.getG().mul(chi[k].redNeg().redMul(wPow)));
                y_0R = y_0R.add(statement['y'].getVector()[witness['index'][0]].mul(psi[k].redNeg().redMul(wPow)));
                gR = gR.add(params.getG().mul(psi[k].redNeg().redMul(wPow)));
                y_XR = y_XR.add(proof.y_XG[k].mul(wPow.neg()));
                p = p.add(P[k].times(wPow));
                q = q.add(Q[k].times(wPow));
                wPow = wPow.redMul(w);
            }
            CRnR = CRnR.add(statement['CRn'].getVector()[witness['index'][0]].mul(wPow));
            y_0R = y_0R.add(statement['y'].getVector()[witness['index'][0]].mul(wPow));
            DR = DR.add(statement['D'].mul(wPow));
            gR = gR.add(params.getG().mul(wPow));
            p = p.add(new FieldVector(Array.from({ length: N }).map((_, i) => i == witness['index'][0] ? wPow : new BN().toRed(bn128.q))));
            q = q.add(new FieldVector(Array.from({ length: N }).map((_, i) => i == witness['index'][1] ? wPow : new BN().toRed(bn128.q))));

            var convolver = new Convolver();
            var y_p = convolver.convolution(p, statement['y']);
            var y_q = convolver.convolution(q, statement['y']);
            vPow = new BN(1).toRed(bn128.q);
            for (var i = 0; i < N; i++) {
                var y_poly = i % 2 ? y_q : y_p;
                y_XR = y_XR.add(y_poly.getVector()[Math.floor(i / 2)].mul(vPow));
                if (i > 0)
                    vPow = vPow.redMul(v);
            }

            var gammaTransfer = bn128.randomScalar();
            var gammaDiff = bn128.randomScalar();
            var zetaTransfer = bn128.randomScalar();
            var zetaDiff = bn128.randomScalar();
            proof.CPrime = params.getH().mul(gammaTransfer.redMul(wPow)).add(y_0R.mul(zetaTransfer));
            proof.DPrime = gR.mul(zetaTransfer);
            proof.CLnPrime = params.getH().mul(gammaDiff.redMul(wPow)).add(y_0R.mul(zetaDiff));
            proof.CRnPrime = gR.mul(zetaDiff);

            var y = utils.hash(ABICoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
            ], [
                bn128.bytes(w),
                bn128.serialize(proof.CPrime),
                bn128.serialize(proof.DPrime),
                bn128.serialize(proof.CLnPrime),
                bn128.serialize(proof.CRnPrime),
            ]));

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
            var lPoly = new FieldVectorPolynomial(aL.plus(z.redNeg()), sL);
            var rPoly = new FieldVectorPolynomial(ys.hadamard(aR.plus(z)).add(twoTimesZs), sR.hadamard(ys));
            var tPolyCoefficients = lPoly.innerProduct(rPoly); // just an array of BN Reds... should be length 3
            var polyCommitment = new PolyCommitment(params, tPolyCoefficients, zs[0].redMul(gammaTransfer).redAdd(zs[1].redMul(gammaDiff)));
            proof.tCommits = new GeneratorVector(polyCommitment.getCommitments()); // just 2 of them

            var x = utils.hash(ABICoder.encodeParameters([
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
            var k_r = bn128.randomScalar();
            var k_vTransfer = bn128.randomScalar();
            var k_vDiff = bn128.randomScalar(); // v "corresponds to" b
            var k_nuTransfer = bn128.randomScalar();
            var k_nuDiff = bn128.randomScalar(); // nu "corresponds to" gamma

            var A_y = gR.mul(k_sk);
            var A_D = params.getG().mul(k_r); // gR........ no longer
            var A_u = utils.gEpoch(statement['epoch']).mul(k_sk);
            var A_X = y_XR.mul(k_r);
            var A_t = DR.add(proof.DPrime).mul(zs[0]).add(CRnR.add(proof.CRnPrime).mul(zs[1])).mul(k_sk);

            var A_C0 = params.getG().mul(k_vTransfer).add(DR.mul(k_sk));
            var A_CLn = params.getG().mul(k_vDiff).add(CRnR.mul(k_sk));
            var A_CPrime = params.getH().mul(k_nuTransfer).add(proof.DPrime.mul(k_sk));
            var A_CLnPrime = params.getH().mul(k_nuDiff).add(proof.CRnPrime.mul(k_sk));

            proof.c = utils.hash(ABICoder.encodeParameters([
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
            ], [
                bn128.bytes(x),
                bn128.serialize(A_y),
                bn128.serialize(A_D),
                bn128.serialize(A_u),
                bn128.serialize(A_X),
                bn128.serialize(A_t),
                bn128.serialize(A_C0),
                bn128.serialize(A_CLn),
                bn128.serialize(A_CPrime),
                bn128.serialize(A_CLnPrime),
            ]));

            proof.s_sk = k_sk.redAdd(proof.c.redMul(witness['sk']));
            proof.s_r = k_r.redAdd(proof.c.redMul(witness['r']));
            proof.s_vTransfer = k_vTransfer.redAdd(proof.c.redMul(witness['bTransfer'].redMul(wPow)));
            proof.s_vDiff = k_vDiff.redAdd(proof.c.redMul(witness['bDiff'].redMul(wPow)));
            proof.s_nuTransfer = k_nuTransfer.redAdd(proof.c.redMul(gammaTransfer.redMul(wPow)));
            proof.s_nuDiff = k_nuDiff.redAdd(proof.c.redMul(gammaDiff.redMul(wPow)));

            var gs = params.getGs();
            var hPrimes = params.getHs().hadamard(ys.invert());
            var hExp = ys.times(z).add(twoTimesZs);
            var P = proof.BA.add(proof.BS.mul(x)).add(gs.sum().mul(z.redNeg())).add(hPrimes.commit(hExp)); // rename of P
            P = P.add(params.getH().mul(proof.mu.redNeg())); // Statement P of protocol 1. should this be included in the calculation of v...?

            var o = utils.hash(ABICoder.encodeParameters([
                'bytes32',
            ], [
                bn128.bytes(proof.c),
            ]));

            var u_x = params.getG().mul(o); // Begin Protocol 1. this is u^x in Protocol 1. use our g for their u, our o for their x.
            P = P.add(u_x.mul(proof.tHat)); // corresponds to P' in protocol 1.
            var primeBase = new GeneratorParams(u_x, gs, hPrimes);
            var ipStatement = { 'primeBase': primeBase, 'P': P };
            var ipWitness = { 'l': lPoly.evaluate(x), 'r': rPoly.evaluate(x) };
            proof.ipProof = ipProver.generateProof(ipStatement, ipWitness, o);

            return proof;
        }
    }
}

module.exports = ZetherProver;