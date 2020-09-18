const ZetherProof = require('../prover/zether.js');
const BurnProof = require('../prover/burn.js');

class Service {
    static proveTransfer(Cn, C, y, epoch, sk, r, bTransfer, bDiff, index, fee) {
        const statement = {};
        statement['Cn'] = Cn;
        statement['C'] = C;
        statement['y'] = y;
        statement['epoch'] = epoch;

        const witness = {};
        witness['sk'] = sk;
        witness['r'] = r;
        witness['bTransfer'] = bTransfer;
        witness['bDiff'] = bDiff;
        witness['index'] = index;

        return ZetherProof.prove(statement, witness, fee);
    };

    static proveBurn(Cn, y, epoch, sender, sk, bDiff) {
        const statement = {};
        statement['Cn'] = Cn;
        statement['y'] = y;
        statement['epoch'] = epoch;
        statement['sender'] = sender;

        const witness = {};
        witness['sk'] = sk;
        witness['bDiff'] = bDiff;

        return BurnProof.prove(statement, witness);
    }
}

module.exports = Service;