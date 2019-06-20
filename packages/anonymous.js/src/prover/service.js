class Service {
    constructor() {
        var zether = new ZetherProver();
        var burn = new BurnProver();

        this.proveTransfer = (CLn, CRn, L, R, y, epoch, x, r, bTransfer, bDiff, index) => { // no longer async.
            // CLn, CRn, Y, x are "live" (point, BN etc)
            // r is a "RedBN". will that cause issues?
            // epoch, bTransfer, bDiff, index are "plain / primitive" JS types.
            var statement = {};
            statement['CLn'] = CLn;
            statement['CRn'] = CRn;
            statement['L'] = L;
            statement['R'] = R;
            statement['y'] = y;
            statement['epoch'] = epoch;

            var witness = {};
            witness['x'] = x;
            witness['r'] = r;
            witness['bTransfer'] = bTransfer;
            witness['bDiff'] = bDiff;
            witness['index'] = index;

            return zether.generateProof(statement, witness);
        }

        this.proveBurn = (CLn, CRn, y, bTransfer, epoch, x, bDiff) => {
            var statement = {};
            statement['CLn'] = CLn;
            statement['CRn'] = CRn;
            statement['y'] = y;
            statement['bTransfer'] = bTransfer;
            statement['epoch'] = epoch;

            var witness = {};
            witness['x'] = x;
            witness['bDiff'] = bDiff;

            return burn.generateProof(statement, witness);
        }
    }
}

module.exports = Service;