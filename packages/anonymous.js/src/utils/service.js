const ZetherProver = require('../prover/zether.js');
const BurnProver = require('../prover/burn.js');

class Service {
    constructor() {
        var zether = new ZetherProver();
        var burn = new BurnProver();

        this.proveTransfer = (CLn, CRn, C, D, y, epoch, sk, r, bTransfer, bDiff, index) => {
            var statement = {};
            statement['CLn'] = CLn;
            statement['CRn'] = CRn;
            statement['C'] = C;
            statement['D'] = D;
            statement['y'] = y;
            statement['epoch'] = epoch;

            var witness = {};
            witness['sk'] = sk;
            witness['r'] = r;
            witness['bTransfer'] = bTransfer;
            witness['bDiff'] = bDiff;
            witness['index'] = index;

            return zether.generateProof(statement, witness).serialize();
        }

        this.proveBurn = (CLn, CRn, y, epoch, sender, sk, bDiff) => {
            var statement = {};
            statement['CLn'] = CLn;
            statement['CRn'] = CRn;
            statement['y'] = y;
            statement['epoch'] = epoch;
            statement['sender'] = sender;

            var witness = {};
            witness['sk'] = sk;
            witness['bDiff'] = bDiff;

            return burn.generateProof(statement, witness).serialize();
        }
    }
}

module.exports = Service;