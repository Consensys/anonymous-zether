const bn128 = require('../utils/bn128.js');
const GeneratorParams = require('../utils/params.js');

class ZetherProver {
    constructor() {
        var params = new GeneratorParams(64);

        this.generateProof = (statement, witness) => {
            var number = witness['bTransfer'].add(witness['bDiff'].shln(32));
            var aL = number.toString(2).padStart(64, '0').split("").map((i) => new BN(i, 10));
            var aR = aL.map((i) => new BN(1).sub(i));
            var alpha = bn128.randomScalar();
            var a = params.commit(aL, aR, alpha);
            var sL = [...Array(64).keys()].map(utils.randomScalar);
            var sR = [...Array(64).keys()].map(utils.randomScalar);

            var rho = bn128.randomScalar();
            var s = params.commit(sL, sR, rho);
        }
    }
}

module.exports = ZetherProver;