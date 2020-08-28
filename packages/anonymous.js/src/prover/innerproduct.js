const ABICoder = require('web3-eth-abi');
const { PedersenVectorCommitment } = require('../utils/algebra.js');
const bn128 = require('../utils/bn128.js');
const utils = require('../utils/utils.js');

class InnerProductProof {
    constructor() {
        this.serialize = () => {
            let result = "0x";
            this.L.forEach((l) => { result += bn128.representation(l).slice(2); });
            this.R.forEach((r) => { result += bn128.representation(r).slice(2); });
            result += bn128.bytes(this.a).slice(2);
            result += bn128.bytes(this.b).slice(2);
            return result;
        };
    }

    static prove(commitment, salt) { // arg: a vector commitment which was decommited.
        const result = new InnerProductProof();
        result.L = [];
        result.R = [];

        const recursiveProof = (result, as, bs, previousChallenge) => { // ref to result
            const n = as.length();
            if (as.length() === 1) {
                result.a = as.getVector()[0];
                result.b = bs.getVector()[0];
                return;
            }
            const nPrime = n / 2; // what if this is not an integer?!?
            const asLeft = as.slice(0, nPrime);
            const asRight = as.slice(nPrime);
            const bsLeft = bs.slice(0, nPrime);
            const bsRight = bs.slice(nPrime);
            const gsLeft = PedersenVectorCommitment.base['gs'].slice(0, nPrime);
            const gsRight = PedersenVectorCommitment.base['gs'].slice(nPrime);
            const hsLeft = PedersenVectorCommitment.base['hs'].slice(0, nPrime);
            const hsRight = PedersenVectorCommitment.base['hs'].slice(nPrime);

            const cL = asLeft.innerProduct(bsRight);
            const cR = asRight.innerProduct(bsLeft);
            const L = gsRight.multiExponentiate(asLeft).add(hsLeft.multiExponentiate(bsRight)).add(PedersenVectorCommitment.base['h'].mul(cL));
            const R = gsLeft.multiExponentiate(asRight).add(hsRight.multiExponentiate(bsLeft)).add(PedersenVectorCommitment.base['h'].mul(cR));
            result.L.push(L);
            result.R.push(R);

            const x = utils.hash(ABICoder.encodeParameters([
                'bytes32',
                'bytes32[2]',
                'bytes32[2]',
            ], [
                bn128.bytes(previousChallenge),
                bn128.serialize(L),
                bn128.serialize(R),
            ]));

            const xInv = x.redInvm();
            PedersenVectorCommitment.base['gs'] = gsLeft.times(xInv).add(gsRight.times(x));
            PedersenVectorCommitment.base['hs'] = hsLeft.times(x).add(hsRight.times(xInv));
            const asPrime = asLeft.times(x).add(asRight.times(xInv));
            const bsPrime = bsLeft.times(xInv).add(bsRight.times(x));

            recursiveProof(result, asPrime, bsPrime, x);

            PedersenVectorCommitment.base['gs'] = gsLeft.concat(gsRight);
            PedersenVectorCommitment.base['hs'] = hsLeft.concat(hsRight); // clean up
        };
        recursiveProof(result, commitment.gValues, commitment.hValues, salt);
        return result;
    }
}

module.exports = InnerProductProof;