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
    static unity = new BN("14a3074b02521e3b1ed9852e5028452693e87be4e910500c7ba9bbddb2f46edd", 16).toRed(bn128.q); // can it be both static and const?
    static unity_inv = new BN("26e5d943cd2c53aced15060255c58a5581bb6108161239002a021f09b39972c9", 16).toRed(bn128.q);
    static two_inv = new BN("183227397098d014dc2822db40c0ac2e9419f4243cdcb848a1f0fac9f8000001", 16).toRed(bn128.q);

    constructor() {
        let base_fft;
        let omegas;
        let inverses;

        const fft = (input, omegas, inverse) => { // crazy... i guess this will work for both points and scalars?
            const size = input.length();
            if (size === 1) return input;
            if (size % 2 !== 0) throw "Input size must be a power of 2!";
            const even = fft(input.extract(0), omegas.extract(0), inverse);
            const odd = fft(input.extract(1), omegas.extract(0), inverse);
            const temp = odd.hadamard(omegas);
            let result = even.add(temp).concat(even.add(temp.negate()));
            if (inverse) result = result.times(Convolver.two_inv);
            return result;
        };

        this.prepare = (base) => {
            const size = base.length();
            const omega = Convolver.unity.redPow(new BN(1).shln(28).div(new BN(size))); // can i right-shift?
            const omega_inv = Convolver.unity_inv.redPow(new BN(1).shln(28).div(new BN(size / 2))); // can i right-shift?
            omegas = new FieldVector([new BN(1).toRed(bn128.q)]);
            inverses = new FieldVector([new BN(1).toRed(bn128.q)]);
            for (let i = 1; i < size / 2; i++) omegas.push(omegas.getVector()[i - 1].redMul(omega));
            for (let i = 1; i < size / 4; i++) inverses.push(inverses.getVector()[i - 1].redMul(omega_inv));
            base_fft = fft(base, omegas, false);
        };

        this.convolution = (exponent) => { // returns only even-indexed outputs of convolution!
            const size = exponent.length();
            const temp = base_fft.hadamard(fft(exponent.flip(), omegas, false));
            return fft(temp.slice(0, size / 2).add(temp.slice(size / 2)).times(Convolver.two_inv), inverses, true);
        }; // using the optimization described here https://dsp.stackexchange.com/a/30699
    }
}

module.exports = { Polynomial, FieldVectorPolynomial, Convolver };