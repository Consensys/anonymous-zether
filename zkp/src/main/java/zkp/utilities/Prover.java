package zkp.utilities;

import edu.stanford.cs.crypto.efficientct.algebra.BN128Point;
import edu.stanford.cs.crypto.efficientct.burnprover.*;
import edu.stanford.cs.crypto.efficientct.zetherprover.*;

import java.math.BigInteger;

public class Prover {

    private ZetherProver<BN128Point> zetherProver = new ZetherProver<>();
    private BurnProver<BN128Point> burnProver = new BurnProver<>();

    public byte[] proveTransfer(byte[] CL, byte[] CR, byte[] yBytes, byte[] yBarBytes, byte[] x, byte[] rBytes, byte[] bTransferBytes, byte[] bDiffBytes) {
        // make sure CL and CR passed in reflect the state of y after it "would be" rolled over...? if you do rolling over at all that is...

        BN128Point g = Params.zetherGenerator();
        BigInteger bTransfer = new BigInteger(1, bTransferBytes);
        BN128Point y = BN128Point.unserialize(yBytes);
        BN128Point yBar = BN128Point.unserialize(yBarBytes);

        BigInteger r = new BigInteger(1, rBytes);

        BN128Point outL = g.multiply(bTransfer).add(y.multiply(r));
        BN128Point inL = g.multiply(bTransfer).add(yBar.multiply(r));
        BN128Point inOutR = g.multiply(r);
//        System.out.println("CL: " + BN128Point.unserialize(CL));
//        System.out.println("CR: " + BN128Point.unserialize(CR));
        BN128Point balanceCommitNewL = BN128Point.unserialize(CL).subtract(outL);
        BN128Point balanceCommitNewR = BN128Point.unserialize(CR).subtract(inOutR);
        ZetherStatement<BN128Point> zetherStatement = new ZetherStatement<>(balanceCommitNewL, balanceCommitNewR, outL, inL, inOutR, y, yBar);
        ZetherWitness zetherWitness = new ZetherWitness(new BigInteger(1, x), r, bTransfer, new BigInteger(1, bDiffBytes));
        ZetherProof<BN128Point> zetherProof = zetherProver.generateProof(Params.getZetherParams(), zetherStatement, zetherWitness);

        System.out.println("bTransfer: " + bTransfer);
        System.out.println("bDiff: " + new BigInteger(1, bDiffBytes));
        System.out.println("outL: " + outL);
        System.out.println("inL: " + inL);
        System.out.println("inOutR: " + inOutR);
        System.out.println("CLn: " + balanceCommitNewL);
        System.out.println("CRn: " + balanceCommitNewR);
        System.out.println("proof length(byte): " + zetherProof.serialize().length);
        return zetherProof.serialize();

    }

    public byte[] proveBurn(byte[] CL, byte[] CR, byte[] yBytes, byte[] bTransferBytes, byte[] x, byte[] bDiff) {
        // again, the contract will immediately roll over, so must fold in STALE pendings

        BN128Point g = Params.burnGenerator();
        BigInteger bTransfer = new BigInteger(1, bTransferBytes);
        BN128Point y = BN128Point.unserialize(yBytes);

        BN128Point balanceCommitNewL = BN128Point.unserialize(CL).subtract(g.multiply(bTransfer));
        BN128Point balanceCommitNewR = BN128Point.unserialize(CR);
        BurnStatement<BN128Point> burnStatement = new BurnStatement<>(balanceCommitNewL, balanceCommitNewR, y, bTransfer);
        BurnWitness burnWitness = new BurnWitness(new BigInteger(1, x), new BigInteger(1, bDiff));
        BurnProof<BN128Point> burnProof = burnProver.generateProof(Params.getBurnParams(), burnStatement, burnWitness);

        System.out.println("CLn: " + balanceCommitNewL);
        System.out.println("CLR: " + balanceCommitNewR);
        System.out.println("proof length(byte): " + burnProof.serialize().length);
        return burnProof.serialize();

    }
}

