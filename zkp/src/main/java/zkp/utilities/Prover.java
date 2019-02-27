package zkp.utilities;

import cyclops.collections.immutable.VectorX;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Group;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Point;
import edu.stanford.cs.crypto.efficientct.burnprover.*;
import edu.stanford.cs.crypto.efficientct.linearalgebra.FieldVector;
import edu.stanford.cs.crypto.efficientct.linearalgebra.GeneratorVector;
import edu.stanford.cs.crypto.efficientct.util.ProofUtils;
import edu.stanford.cs.crypto.efficientct.zetherprover.*;

import java.math.BigInteger;

public class Prover {

    private ZetherProver<BN128Point> zetherProver = new ZetherProver<>();
    private BurnProver<BN128Point> burnProver = new BurnProver<>();

    public byte[] proveTransfer(byte[][] CL, byte[][] CR, byte[][] yBytes, byte[] x, byte[] rBytes, byte[] bTransferBytes, byte[] bDiffBytes, byte[] outIndexBytes, byte[] inIndexBytes) {
        // make sure CL and CR passed in reflect the state of y after it "would be" rolled over...? if you do rolling over at all that is...

        int size = yBytes.length;
        BN128Group group = Params.getGroup();
        BigInteger q = group.groupOrder();
        BN128Point g = Params.zetherGenerator();

        BigInteger r = new BigInteger(1, rBytes);
        GeneratorVector<BN128Point> y = GeneratorVector.from(VectorX.range(0, size).map(i -> BN128Point.unserialize(yBytes[i])), group);
        GeneratorVector<BN128Point> L = y.times(r); // this function is new, test it
        int outIndex = new BigInteger(1, outIndexBytes).intValue();
        int inIndex = new BigInteger(1, inIndexBytes).intValue();
        BigInteger bTransfer = new BigInteger(1, bTransferBytes);
        L.get(outIndex).subtract(g.multiply(bTransfer));
        L.get(inIndex).add(g.multiply(bTransfer));
        BN128Point R = g.multiply(r);
        GeneratorVector<BN128Point> balanceCommitNewL = L.add(VectorX.range(0, size).map(i -> BN128Point.unserialize(CL[i])));
        GeneratorVector<BN128Point> balanceCommitNewR = GeneratorVector.from(VectorX.range(0, size).map(i -> BN128Point.unserialize(CR[i]).add(R)), group);

//        System.out.println("CL: " + BN128Point.unserialize(CL));
//        System.out.println("CR: " + BN128Point.unserialize(CR));
        ZetherStatement<BN128Point> zetherStatement = new ZetherStatement<>(balanceCommitNewL, balanceCommitNewR, L, R, y);
        ZetherWitness zetherWitness = new ZetherWitness(new BigInteger(1, x), r, bTransfer, new BigInteger(1, bDiffBytes), outIndex, inIndex);
        ZetherProof<BN128Point> zetherProof = zetherProver.generateProof(Params.getZetherParams(), zetherStatement, zetherWitness);

        System.out.println("bTransfer: " + bTransfer);
        System.out.println("bDiff: " + new BigInteger(1, bDiffBytes));
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

