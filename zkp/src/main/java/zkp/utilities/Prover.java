package zkp.utilities;

import edu.stanford.cs.crypto.efficientct.GeneratorParams;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Group;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Point;
import edu.stanford.cs.crypto.efficientct.burnprover.*;
import edu.stanford.cs.crypto.efficientct.zetherprover.*;

import java.math.BigInteger;

public class Prover {

    private static final BN128Group group = new BN128Group();
    private static final BN128Point g = group.generator();
    private static final BigInteger q = group.groupOrder();
    private static final BigInteger MAX = BigInteger.valueOf(4294967296L); // one less than this, actually...

    private GeneratorParams<BN128Point> zetherParams = GeneratorParams.generateParams(64, group);
    private ZetherProver<BN128Point> zetherProver = new ZetherProver<>();

    private GeneratorParams<BN128Point> burnParams = GeneratorParams.generateParams(32, group);
    private BurnProver<BN128Point> burnProver = new BurnProver<>();

    public byte[] proveTransfer(byte[] CL, byte[] CR, byte[] yBytes, byte[] yBarBytes, byte[] x, byte[] rBytes, byte[] bTransferBytes, byte[] bDiff) {
        // make sure CL and CR passed in reflect the state of y after it "would be" rolled over...? if you do rolling over at all that is...
        BigInteger bTransfer = new BigInteger(1, bTransferBytes);
        BN128Point y = BN128Point.unserialize(yBytes);
        BN128Point yBar = BN128Point.unserialize(yBarBytes);

        BigInteger r = new BigInteger(1, rBytes);

        BN128Point outL = g.multiply(bTransfer).add(y.multiply(r));
        BN128Point inL = g.multiply(bTransfer).add(yBar.multiply(r));
        BN128Point inOutR = g.multiply(r);
        BN128Point balanceCommitNewL = BN128Point.unserialize(CL).subtract(outL);
        BN128Point balanceCommitNewR = BN128Point.unserialize(CR).subtract(inOutR);
        ZetherStatement<BN128Point> zetherStatement = new ZetherStatement<>(balanceCommitNewL, balanceCommitNewR, outL, inL, inOutR, y, yBar);
        ZetherWitness zetherWitness = new ZetherWitness(new BigInteger(1, x), r, bTransfer, new BigInteger(1, bDiff));
        ZetherProof<BN128Point> zetherProof = zetherProver.generateProof(zetherParams, zetherStatement, zetherWitness);

        return zetherProof.serialize();
    }

    public byte[] proveBurn(byte[] CL, byte[] CR, byte[] yBytes, byte[] bTransferBytes, byte[] x, byte[] bDiff) {
        // again, the contract will immediately roll over, so must fold in STALE pendings
        BigInteger bTransfer = new BigInteger(1, bTransferBytes);
        BN128Point y = BN128Point.unserialize(yBytes);

        BN128Point balanceCommitNewL = BN128Point.unserialize(CL).subtract(g.multiply(bTransfer));
        BN128Point balanceCommitNewR = BN128Point.unserialize(CR);
        BurnStatement<BN128Point> burnStatement = new BurnStatement<>(balanceCommitNewL, balanceCommitNewR, y, bTransfer);
        BurnWitness burnWitness = new BurnWitness(new BigInteger(1, x), new BigInteger(1, bDiff));
        BurnProof<BN128Point> burnProof = burnProver.generateProof(burnParams, burnStatement, burnWitness);

        return burnProof.serialize();
    }
}

