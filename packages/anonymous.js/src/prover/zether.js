const { AbiCoder } = require('web3-eth-abi');
const BN = require('bn.js');

const bn128 = require('../utils/bn128.js');
const utils = require('../utils/utils.js');
const { Convolver, FieldVector, FieldVectorPolynomial, GeneratorParams, GeneratorVector, PolyCommitment } = require('./algebra.js');
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
            result += bn128.representation(this.CLnG).slice(2);
            result += bn128.representation(this.CRnG).slice(2);
            this.CG.forEach((CG_j) => {
                CG_j.getVector().forEach((CG_ji) => {
                    result += bn128.representation(CG_ji).slice(2);
                });
            });
            this.yG.forEach((yG_j) => {
                yG_j.getVector().forEach((yG_ji) => {
                    result += bn128.representation(yG_ji).slice(2);
                });
            });
            result += bn128.representation(this.DG).slice(2);
            result += bn128.representation(this.gG).slice(2);

            this.f.forEach((f_j) => {
                f_j.getVector().forEach((f_ji) => {
                    result += bn128.bytes(f_ji).slice(2);
                });
            });

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
        var abiCoder = new AbiCoder();

        var params = new GeneratorParams();
        params.extend(64);
        var ipProver = new InnerProductProver();

        this.generateProof = (statement, witness) => {
            var proof = new ZetherProof();

            var statementHash = utils.hash(abiCoder.encodeParameters([
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

            var size = statement['y'].length(); // begin one out of many proving.
            if (params.size() < size) {
                params.extend(size);
            } // one-off cost when a "new record" size is used.
            var r_P = bn128.randomScalar();
            var r_Q = bn128.randomScalar();
            var r_U = bn128.randomScalar();
            var r_V = bn128.randomScalar();
            var r_X = bn128.randomScalar();
            var r_Y = bn128.randomScalar();
            var sigma = bn128.randomScalar();
            var p = Array.from({ length: 2 }).map(() => Array.from({ length: size - 1 }).map(bn128.randomScalar));
            p = p.map((p_j) => {
                p_j.unshift(new FieldVector(p_j).sum().redNeg());
                return new FieldVector(p_j);
            });
            var q = Array.from({ length: 2 }).map((_, j) => new FieldVector(Array.from({ length: size }).map((_, i) => witness['index'][j] == i ? new BN(1).toRed(bn128.q) : new BN(0).toRed(bn128.q))));
            var u = p.map((p_j, j) => p_j.hadamard(q[j].times(new BN(2).toRed(bn128.q)).negate().plus(new BN(1).toRed(bn128.q))));
            var v = p.map((p_j) => p_j.hadamard(p_j).negate())
            proof.P = params.commit(p[0], p[1], r_P);
            proof.Q = params.commit(q[0], q[1], r_Q);
            proof.U = params.commit(u[0], u[1], r_U);
            proof.V = params.commit(v[0], v[1], r_V);
            var cycler = p.map((p_j) => new FieldVector(Array.from({ length: 2 }).map((_, i) => p_j.extract(i).sum())));
            proof.X = params.commit(cycler[0].hadamard(cycler[1]).extract(0), cycler[0].hadamard(cycler[1]).extract(1), r_X);
            proof.Y = params.commit(cycler[witness['index'][1] % 2].extract(0), cycler[witness['index'][0] % 2].extract(1), r_Y);

            proof.CLnG = statement['CLn'].commit(p[0]).add(statement['CLn'].getVector()[witness['index'][0]].add(params.getG().mul(witness['bDiff'].redNeg())).mul(sigma));
            proof.CRnG = statement['CRn'].commit(p[0]).add(statement['CRn'].getVector()[witness['index'][0]].mul(sigma));
            var convolver = new Convolver();
            proof.CG = p.map((p_j, j) => convolver.convolution(p_j, statement['C']).add(statement['y'].shift(witness['index'][j]).extract(0).times(sigma.mul(witness['r']))));
            proof.yG = p.map((p_j, j) => convolver.convolution(p_j, statement['y']).add(statement['y'].shift(witness['index'][j]).extract(0).times(sigma)));
            proof.DG = statement['D'].mul(sigma);
            proof.gG = params.getG().mul(sigma);

            var w = utils.hash(abiCoder.encodeParameters([
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
                'bytes32[2]',
                'bytes32[2][2][]',
                'bytes32[2][2][]',
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
                bn128.serialize(proof.CLnG),
                bn128.serialize(proof.CRnG),
                proof.CG[0].getVector().map((point, i) => [point, proof.CG[1].getVector()[i]].map(bn128.serialize)),
                proof.yG[0].getVector().map((point, i) => [point, proof.yG[1].getVector()[i]].map(bn128.serialize)),
                bn128.serialize(proof.DG),
                bn128.serialize(proof.gG),
            ]));

            proof.f = p.map((p_j, j) => new FieldVector(p_j.add(q[j].times(w)).getVector().slice(1)));
            proof.z_P = r_Q.redMul(w).redAdd(r_P);
            proof.z_U = r_U.redMul(w).redAdd(r_V);
            proof.z_X = r_Y.redMul(w).redAdd(r_X);

            var CRn2 = statement['CRn'].getVector()[witness['index'][0]].mul(w.redSub(sigma));
            var y2 = Array.from({ length: 2 }).map((_, j) => statement['y'].shift(witness['index'][j]).extract(0).times(w.redSub(sigma)));
            var D2 = statement['D'].mul(w.redSub(sigma));
            var g2 = params.getG().mul(w.redSub(sigma));

            var gammaTransfer = bn128.randomScalar();
            var gammaDiff = bn128.randomScalar();
            var zetaTransfer = bn128.randomScalar();
            var zetaDiff = bn128.randomScalar();
            proof.CPrime = params.getH().mul(gammaTransfer.redMul(w)).add(y2[0].getVector()[0].mul(zetaTransfer));
            proof.DPrime = g2.mul(zetaTransfer);
            proof.CLnPrime = params.getH().mul(gammaDiff.redMul(w)).add(y2[0].getVector()[0].mul(zetaDiff));
            proof.CRnPrime = g2.mul(zetaDiff);

            var y = utils.hash(abiCoder.encodeParameters([
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
            var k_r = bn128.randomScalar();
            var k_vTransfer = bn128.randomScalar();
            var k_vDiff = bn128.randomScalar(); // v "corresponds to" b
            var k_nuTransfer = bn128.randomScalar();
            var k_nuDiff = bn128.randomScalar(); // nu "corresponds to" gamma

            var A_y = g2.mul(k_sk);
            var A_D = g2.mul(k_r);
            var A_u = utils.gEpoch(statement['epoch']).mul(k_sk);
            var A_B = y2[0].getVector()[0].add(y2[1].getVector()[0]).mul(k_r);
            var A_C = y2.map((y2_j) => new GeneratorVector(y2_j.times(k_r).getVector().slice(1)));
            var A_t = D2.add(proof.DPrime).mul(zs[0]).add(CRn2.add(proof.CRnPrime).mul(zs[1])).mul(k_sk);

            var A_C00 = params.getG().mul(k_vTransfer).add(D2.mul(k_sk));
            var A_CLn = params.getG().mul(k_vDiff).add(CRn2.mul(k_sk));
            var A_CPrime = params.getH().mul(k_nuTransfer).add(proof.DPrime.mul(k_sk));
            var A_CLnPrime = params.getH().mul(k_nuDiff).add(proof.CRnPrime.mul(k_sk));

            proof.c = utils.hash(abiCoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2]',
                'bytes32[2][2][]',
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
                bn128.serialize(A_B),
                A_C[0].getVector().map((point, i) => [point, A_C[1].getVector()[i]].map(bn128.serialize)), // unusual---have to transpose
                bn128.serialize(A_t),
                bn128.serialize(A_C00),
                bn128.serialize(A_CLn),
                bn128.serialize(A_CPrime),
                bn128.serialize(A_CLnPrime),
            ]));

            proof.s_sk = k_sk.redAdd(proof.c.redMul(witness['sk']));
            proof.s_r = k_r.redAdd(proof.c.redMul(witness['r']));
            proof.s_vTransfer = k_vTransfer.redAdd(proof.c.redMul(witness['bTransfer'].redMul(w)));
            proof.s_vDiff = k_vDiff.redAdd(proof.c.redMul(witness['bDiff'].redMul(w)));
            proof.s_nuTransfer = k_nuTransfer.redAdd(proof.c.redMul(gammaTransfer.redMul(w)));
            proof.s_nuDiff = k_nuDiff.redAdd(proof.c.redMul(gammaDiff.redMul(w)));

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

module.exports = ZetherProver;