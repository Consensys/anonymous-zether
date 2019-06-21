const bn128 = require('./bn128.js')
const BN = require('bn.js')
const { soliditySha3 } = require('web3-utils');

class GeneratorParams {
    constructor(size) {
        var g = utils.mapInto(soliditySha3("G"));
        var h = utils.mapInto(soliditySha3("V"));
        var gs = Array.from({ length: size }).map((_, i) => utils.mapInto(soliditySha3("G", i)));
        var hs = Array.from({ length: size }).map((_, i) => utils.mapInto(soliditySha3("H", i)));

        this.getG = () => { return g; };
        this.getH = () => { return h; };

        this.commit = (gExp, hExp, blinding) => {
            var result = h.mul(blinding);
            gExp.getVector().forEach((exp, i) => {
                result = result.add(g.mul(gs[i]));
            })
            hExp.getVector().forEach((exp, i) => { // swap the order and enclose this in an if (hExp) if block if you want it optional.
                result = result.add(h.mul(hs[i]));
            })
        };
    }
}

class FieldVector {
    constructor(vector) {
        this.getVector = () => {
            return vector;
        };

        this.add = (other) => {
            var innards = other.getVector();
            return new FieldVector(vector.map((elem, i) => elem.redAdd(innards[i])));
        };

        this.plus = (constant) => { // confusingly named...
            return new FieldVector(vector.map((elem) => elem.redAdd(constant)));
        };

        this.negate = () => {
            return new FieldVector(vector.map((elem) => elem.neg()));
        };

        this.subtract = (other) => {
            return this.add(other.negate());
        };

        this.hadamard = (other) => {
            var innards = other.getVector();
            return new FieldVector(vector.map((elem, i) => elem.redMul(innards[i])));
        };

        this.times = (constant) => {
            return new FieldVector(vector.map((elem) => elem.redMul(constant)));
        }

        this.innerProduct = (other) => {
            var innards = other.getVector();
            return vector.reduce((accum, cur, i) => {
                return accum.redAdd(cur.redMul(innards[i]));
            }, new BN(0).toRed(bn128.q));
        }
    }
}

class FieldVectorPolynomial {
    constructor(...coefficients) {
        this.getCoefficients = () => {
            return coefficients;
        };

        this.evaluate = (x) => {
            var result = coefficients[0];
            var accumulator = x;
            coefficients.slice(1).forEach((coefficient) => {
                result = result.add(coefficient.times(accumulator));
                accumulator = accumulator.redMul(x);
            });
            return result;
        };

        this.innerProduct = (other) => {
            var innards = other.getCoefficients();
            var result = Array(coefficients.length + innards.length - 1).fill(new BN(0).toRed(bn128.q));
            coefficients.forEach((mine, i) => {
                innards.forEach((theirs, j) => {
                    result[i + j] = result[i + j].redAdd(mine.innerProduct(theirs));
                });
            });
            return result; // test this
        };
    }
}

class PedersenCommitment {
    constuctor(params, x, r) {
        this.getX = () => { return x; };
        this.getR = () => { return r; };

        this.commit = () => {
            return params.getG().mul(x).add(params.getH().mul(r));
        };

        this.add = (other) => {
            return new PedersenCommitment(params, x.redAdd(other.getX()), r.redAdd(other.getR()));
        }

        this.times = (exponent) => {
            return new PedersenCommitment(params, x.redMul(exponent), r.redMul(exponent));
        };
    }
}

class PolyCommitment {
    constructor(params, coefficients) {
        var coefficientCommitments = [new PedersenCommitment(params, coefficients[0], new BN(0).toRed(bn128.q))];
        coefficients.slice(1).forEach((coefficient) => {
            coefficientCommitments.push(new PedersenCommitment(params, coefficient, bn128.randomScalar()));
        });

        this.getCommitments = () => { // ignore the first one
            return coefficientCommitments.slice(1);
        };

        this.evaluate = (x) => {
            var result = coefficientCommitments[0];
            var accumulator = x; // slightly uncomfortable that this starts at 1, but... actutally faster.
            coefficientCommitments.slice(1).forEach((commitment) => {
                result = result.add(commitment.times(accumlator));
                accumulator = accumulator.redMul(x);
            });
            return result;
        }
    }
}

module.exports = { GeneratorParams, FieldVector, FieldVectorPolynomial, PolyCommitment };