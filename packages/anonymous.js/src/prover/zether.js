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
            result += bn128.representation(this.A).slice(2);
            result += bn128.representation(this.S).slice(2);
            result += bn128.representation(this.P).slice(2);
            result += bn128.representation(this.Q).slice(2);
            result += bn128.representation(this.U).slice(2);
            result += bn128.representation(this.V).slice(2);
            result += bn128.representation(this.X).slice(2);
            result += bn128.representation(this.Y).slice(2);

            this.CLnG.forEach((CLnG_i) => { result += bn128.representation(CLnG_i).slice(2); });
            this.CRnG.forEach((CRnG_i) => { result += bn128.representation(CRnG_i).slice(2); });
            this.C_0G.forEach((C_0G_i) => { result += bn128.representation(C_0G_i).slice(2); });
            this.y_0G.forEach((y_0G_i) => { result += bn128.representation(y_0G_i).slice(2); });
            this.C_XG.forEach((C_XG_i) => { result += bn128.representation(C_XG_i).slice(2); });
            this.y_XG.forEach((y_XG_i) => { result += bn128.representation(y_XG_i).slice(2); });
            this.DG.forEach((DG_i) => { result += bn128.representation(DG_i).slice(2); });
            this.gG.forEach((gG_i) => { result += bn128.representation(gG_i).slice(2); });
            this.f.forEach((f_i) => { result += bn128.bytes(f_i).slice(2); });

            result += bn128.bytes(this.z_P).slice(2);
            result += bn128.bytes(this.z_U).slice(2);
            result += bn128.bytes(this.z_X).slice(2);

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

        var recursivePolynomials = (list, accum, p, q) => {
            // ps, qs are log(N)-lengthed.
            // returns N-length list of coefficient vectors
            // should take about N log N to compute.
            if (p.length == 0) {
                list.push(accum.coefficients);
                return;
            }
            var pTop = p.pop();
            var qTop = q.pop();
            var left = new Polynomial([pTop.getVector()[0], qTop.getVector()[0]]);
            var right = new Polynomial([pTop.getVector()[1], qTop.getVector()[1]]);
            recursivePolynomials(list, accum.mul(left), p, q);
            recursivePolynomials(list, accum.mul(right), p, q);
            p.push(pTop);
            q.push(qTop);
        }

        this.generateProof = (statement, witness) => {
            var proof = new ZetherProof();

            var statementHash = utils.hash(ABICoder.encodeParameters([
                'bytes32[2][]',
                'bytes32[2][]',
                'bytes32[2][]',
                'bytes32[2]',
                'bytes32[2][]',
                'uint256'
            ], [
                statement['CLn'],
                statement['CRn'],
                statement['C'],
                statement['D'],
                statement['y'],
                statement['epoch']
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
            proof.A = params.commit(aL, aR, alpha);
            var sL = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
            var sR = new FieldVector(Array.from({ length: 64 }).map(bn128.randomScalar));
            var rho = bn128.randomScalar(); // already reduced
            proof.S = params.commit(sL, sR, rho);

            var N = statement['y'].length();
            if (N & (N - 1))
                throw "Size must be a power of 2!"; // probably unnecessary... this won't be called directly.
            var m = new BN(N).bitLength() - 1; // assuming that N is a power of 2?
            // DON'T need to extend the params anymore. 64 will always be enough.
            var r_P = bn128.randomScalar();
            var r_Q = bn128.randomScalar();
            var r_U = bn128.randomScalar();
            var r_V = bn128.randomScalar();
            var r_X = bn128.randomScalar();
            var r_Y = bn128.randomScalar();
            var p = Array.from({ length: 2 * m }).map(bn128.randomScalar).map((p_i) => new FieldVector([p_i.redNeg(), p_i]));
            var q = (new BN(witness['index'][1]).toString(2, m) + new BN(witness['index'][0]).toString(2, m)).split("").reverse().map((i) => new FieldVector([new BN(1).sub(new BN(i, 2)).toRed(bn128.q), new BN(i, 2).toRed(bn128.q)]));
            var u = p.map((p_i, i) => p_i.hadamard(q[i].times(new BN(2).toRed(bn128.q)).negate().plus(new BN(1).toRed(bn128.q))));
            var v = p.map((p_i) => p_i.hadamard(p_i).negate())
            proof.P = params.commitRows(p, r_P);
            proof.Q = params.commitRows(q, r_Q);
            proof.U = params.commitRows(u, r_U);
            proof.V = params.commitRows(v, r_V);
            proof.X = params.commitRows([p[0].hadamard(p[m])], r_X);
            proof.Y = params.commitRows([p[0].hadamard(q[m]).add(p[m].hadamard(q[0]))], r_Y);

            var d = utils.hash(ABICoder.encodeParameters([
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
                bn128.serialize(proof.A),
                bn128.serialize(proof.S),
                bn128.serialize(proof.P),
                bn128.serialize(proof.Q),
                bn128.serialize(proof.U),
                bn128.serialize(proof.V),
                bn128.serialize(proof.X),
                bn128.serialize(proof.Y),
            ]));

            var pi = Array.from({ length: m }).map(bn128.randomScalar);
            var sigma_0 = Array.from({ length: m }).map(bn128.randomScalar); // for sender
            var sigma_X = Array.from({ length: m }).map(bn128.randomScalar); // for sender, recipient and the rest.

            var poly_0 = [];
            var poly_1 = [];
            recursivePolynomials(poly_0, new Polynomial(), p.slice(0, m), q.slice(0, m));
            recursivePolynomials(poly_1, new Polynomial(), p.slice(m), q.slice(m));
            poly_0 = Array.from({ length: m }).map((_, i) => new FieldVector(poly_0.map((poly_0_j) => poly_0_j[i])));
            poly_1 = Array.from({ length: m }).map((_, i) => new FieldVector(poly_1.map((poly_1_j) => poly_1_j[i])));

            proof.CLnG = Array.from({ length: m }).map((_, i) => statement['CLn'].commit(poly_0[i]).add(statement['y'].getVector()[witness['index'][0]].mul(pi[i])));
            proof.CRnG = Array.from({ length: m }).map((_, i) => statement['CRn'].commit(poly_0[i]).add(params.getG().mul(pi[i])));
            proof.C_0G = Array.from({ length: m }).map((_, i) => statement['C'].commit(poly_0[i]).add(statement['y'].getVector()[witness['index'][0]].mul(witness['r'].redMul(sigma_0[i]))));
            proof.y_0G = Array.from({ length: m }).map((_, i) => statement['y'].commit(poly_0[i]).add(statement['y'].getVector()[witness['index'][0]].mul(sigma_0[i])));
            proof.C_XG = Array.from({ length: m }).map((_, i) => statement['D'].mul(sigma_X[i]));
            proof.y_XG = Array.from({ length: m }).map((_, i) => params.getG().mul(sigma_X[i]));
            var dPow = new BN(1).toRed(bn128.q);
            for (var j = 0; j < N; j++) { // could turn this into a complicated reduce, but...
                var temp = params.getG().mul(witness['bTransfer'].redMul(dPow));
                var poly = j % 2 ? poly_1 : poly_0; // clunky, i know, etc. etc.
                proof.C_XG = proof.C_XG.map((C_XG_i, i) => C_XG_i.add(temp.mul(poly[i].getVector()[(witness['index'][0] + N - (j - j % 2)) % N].redSub(poly[i].getVector()[(witness['index'][1] + N - (j - j % 2)) % N]))));
                if (j != 0)
                    dPow = dPow.redMul(d);
            }
            proof.DG = Array.from({ length: m }).map((_, i) => statement['D'].mul(sigma_0[i]));
            proof.gG = Array.from({ length: m }).map((_, i) => params.getG().mul(sigma_0[i]));

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
                bn128.bytes(d),
                proof.CLnG.map(bn128.serialize),
                proof.CRnG.map(bn128.serialize),
                proof.C_0G.map(bn128.serialize),
                proof.y_0G.map(bn128.serialize),
                proof.C_XG.map(bn128.serialize),
                proof.y_XG.map(bn128.serialize),
                proof.DG.map(bn128.serialize),
                proof.gG.map(bn128.serialize),
            ]));

            proof.f = p.map((p_i, i) => p_i.getVector()[1].redAdd(q[i].getVector()[1].redMul(w)));
            proof.z_P = r_Q.redMul(w).redAdd(r_P);
            proof.z_U = r_U.redMul(w).redAdd(r_V);
            proof.z_X = r_Y.redMul(w).redAdd(r_X);

            var CRnR = bn128.zero;
            var y_0R = bn128.zero;
            var y_XR = bn128.zero;
            var DR = bn128.zero;
            var gR = bn128.zero;
            var f_0 = new FieldVector(Array.from({ length: N }).map(() => new BN().toRed(bn128.q))); // evaluations of poly_0 and poly_1 at w.
            var f_1 = new FieldVector(Array.from({ length: N }).map(() => new BN().toRed(bn128.q))); // verifier will compute these using f.

            var wPow = new BN(1).toRed(bn128.q);
            for (var i = 0; i < m; i++) {
                CRnR = CRnR.add(params.getG().mul(pi[i].redNeg().redMul(wPow)));
                y_0R = y_0R.add(statement['y'].getVector()[witness['index'][0]].mul(sigma_0[i].redNeg().redMul(wPow)));
                y_XR = y_XR.add(proof.y_XG[i].mul(wPow.neg()));
                DR = DR.add(statement['D'].mul(sigma_0[i].redNeg().redMul(wPow)));
                gR = gR.add(params.getG().mul(sigma_0[i].redNeg().redMul(wPow)));
                f_0 = f_0.add(poly_0[i].times(wPow));
                f_1 = f_1.add(poly_1[i].times(wPow));
                wPow = wPow.redMul(w);
            }
            CRnR = CRnR.add(statement['CRn'].getVector()[witness['index'][0]].mul(wPow));
            y_0R = y_0R.add(statement['y'].getVector()[witness['index'][0]].mul(wPow));
            DR = DR.add(statement['D'].mul(wPow));
            gR = gR.add(params.getG().mul(wPow));
            f_0 = f_0.add(new FieldVector(Array.from({ length: N }).map((_, i) => i == witness['index'][0] ? wPow : new BN().toRed(bn128.q))));
            f_1 = f_1.add(new FieldVector(Array.from({ length: N }).map((_, i) => i == witness['index'][1] ? wPow : new BN().toRed(bn128.q))));

            var convolver = new Convolver();
            var y_poly_0 = convolver.convolution(f_0, statement['y']);
            var y_poly_1 = convolver.convolution(f_1, statement['y']);
            dPow = new BN(1).toRed(bn128.q);
            for (var j = 0; j < N; j++) {
                var y_poly = j % 2 ? y_poly_1 : y_poly_0;
                y_XR = y_XR.add(y_poly.getVector()[Math.floor(j / 2)].mul(dPow));
                if (j != 0)
                    dPow = dPow.redMul(d);
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
            var hsPrime = params.getHs().hadamard(ys.invert());
            var hExp = ys.times(z).add(twoTimesZs);
            var Z = proof.A.add(proof.S.mul(x)).add(gs.sum().mul(z.redNeg())).add(hsPrime.commit(hExp)); // rename of P
            Z = Z.add(params.getH().mul(proof.mu.redNeg())); // Statement P of protocol 1. should this be included in the calculation of v...?

            var o = utils.hash(ABICoder.encodeParameters([
                'bytes32',
            ], [
                bn128.bytes(proof.c),
            ]));

            var u_x = params.getG().mul(o); // Begin Protocol 1. this is u^x in Protocol 1. use our g for their u, our o for their x.
            var ZPrime = Z.add(u_x.mul(proof.tHat)); // corresponds to P' in protocol 1.
            var primeBase = new GeneratorParams(u_x, gs, hsPrime);
            var ipStatement = { 'primeBase': primeBase, 'P': ZPrime };
            var ipWitness = { 'l': lPoly.evaluate(x), 'r': rPoly.evaluate(x) };
            proof.ipProof = ipProver.generateProof(ipStatement, ipWitness, o);

            return proof;
        }
    }
}

module.exports = ZetherProver;