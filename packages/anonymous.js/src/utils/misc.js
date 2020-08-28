const bn128 = require('../utils/bn128.js');
const BN = require('bn.js');

const { FieldVector } = require('./algebra.js');

class Polynomial {
    constructor(coefficients) {
        this.coefficients = coefficients; // vector of coefficients, _little_ endian.
        this.mul = (other) => { // i assume that other has coeffs.length == 2, and monic if linear.
            const product = this.coefficients.map((coefficient) => coefficient.redMul(other.coefficients[0]));
            product.push(new BN(0).toRed(bn128.q));
            if (other.coefficients[1].eqn(1)) this.coefficients.forEach((elem, i) => product[i + 1] = product[i + 1].redAdd(elem));
            return new Polynomial(product);
        }
    }
}

class FieldVectorPolynomial {
    constructor(...coefficients) { // an array of fieldvectors (2 in practice, but could be arbitrary).
        this.getCoefficients = () => coefficients;

        this.evaluate = (x) => {
            let result = coefficients[0];
            let accumulator = x;
            coefficients.slice(1).forEach((coefficient) => {
                result = result.add(coefficient.times(accumulator));
                accumulator = accumulator.redMul(x);
            });
            return result;
        };

        this.innerProduct = (other) => {
            const result = Array(coefficients.length + other.getCoefficients().length - 1).fill(new BN(0).toRed(bn128.q));
            other.getCoefficients().forEach((theirs, i) => {
                coefficients.forEach((mine, j) => {
                    result[i + j] = result[i + j].redAdd(mine.innerProduct(theirs));
                });
            });
            return result; // just a plain array?
        };
    }
}

class Convolver {
    constructor() {
        const unity = new BN("14a3074b02521e3b1ed9852e5028452693e87be4e910500c7ba9bbddb2f46edd", 16).toRed(bn128.q);
        // this can technically be "static" (as in the "module pattern", like bn128), but...

        const fft = (input, inverse) => { // crazy... i guess this will work for both points and scalars?
            const length = input.length();
            if (length === 1) return input;
            if (length % 2 !== 0) throw "Input size must be a power of 2!";
            let omega = unity.redPow(new BN(1).shln(28).div(new BN(length)));
            if (inverse) omega = omega.redInvm();
            const even = fft(input.extract(0), inverse);
            const odd = fft(input.extract(1), inverse);
            let omegas = [new BN(1).toRed(bn128.q)];
            for (let i = 1; i < length / 2; i++) omegas.push(omegas[i - 1].redMul(omega));
            omegas = new FieldVector(omegas);
            let result = even.add(odd.hadamard(omegas)).concat(even.add(odd.hadamard(omegas).negate()));
            if (inverse) result = result.times(new BN(2).toRed(bn128.q).redInvm());
            return result;
        };

        this.convolution = (exponent, base) => { // returns only even-indexed outputs of convolution!
            const size = base.length();
            const temp = fft(base, false).hadamard(fft(exponent.flip(), false));
            return fft(temp.slice(0, size / 2).add(temp.slice(size / 2)).times(new BN(2).toRed(bn128.q).redInvm()), true);
        }; // using the optimization described here https://dsp.stackexchange.com/a/30699
    }
}

module.exports = { Polynomial, FieldVectorPolynomial, Convolver };