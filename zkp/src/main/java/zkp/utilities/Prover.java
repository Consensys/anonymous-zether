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
import java.util.Arrays;

public class Prover {

    private ZetherProver<BN128Point> zetherProver = new ZetherProver<>();
    private BurnProver<BN128Point> burnProver = new BurnProver<>();

    public byte[] proveTransfer(byte[][] CL, byte[][] CR, byte[][] yBytes, byte[] gEpochBytes, byte[] xBytes, byte[] rBytes, byte[] bTransferBytes, byte[] bDiffBytes, byte[] indexBytes) {
        // indexBytes is a concatenation of the 32 bytes respectively of outIndex and inIndex.
        int size = yBytes.length;
        BN128Group group = Params.getGroup();
        BN128Point g = Params.zetherGenerator();
        BigInteger q = group.groupOrder();

        BigInteger b = new BigInteger(1, bTransferBytes);
        BigInteger r = new BigInteger(1, rBytes);
        GeneratorVector<BN128Point> y = GeneratorVector.from(VectorX.range(0, size).map(i -> BN128Point.unserialize(yBytes[i])), group);
        int[] index = new int[]{new BigInteger(1, Arrays.copyOfRange(indexBytes, 0, 32)).intValue(), new BigInteger(1, Arrays.copyOfRange(indexBytes, 32, 64)).intValue()};
        FieldVector bTransfer = FieldVector.from(VectorX.range(0, size).map(i -> i == index[0] ? b.negate() : i == index[1] ? b : BigInteger.ZERO), q);
        GeneratorVector<BN128Point> L = y.times(r).add(bTransfer.getVector().map(g::multiply)); // this function is new, test it
        BN128Point R = g.multiply(r);
        GeneratorVector<BN128Point> balanceCommitNewL = L.add(VectorX.range(0, size).map(i -> BN128Point.unserialize(CL[i])));
        GeneratorVector<BN128Point> balanceCommitNewR = GeneratorVector.from(VectorX.range(0, size).map(i -> BN128Point.unserialize(CR[i]).add(R)), group);

//        System.out.println("CL: " + BN128Point.unserialize(CL));
//        System.out.println("CR: " + BN128Point.unserialize(CR));
        BigInteger x = new BigInteger(1, xBytes);
        BN128Point gEpoch = BN128Point.unserialize(gEpochBytes);
        BN128Point u = gEpoch.multiply(x);
        ZetherStatement<BN128Point> zetherStatement = new ZetherStatement<>(balanceCommitNewL, balanceCommitNewR, L, R, y, gEpoch, u);
        ZetherWitness zetherWitness = new ZetherWitness(x, r, b, new BigInteger(1, bDiffBytes), index);
        ZetherProof<BN128Point> zetherProof = zetherProver.generateProof(Params.getZetherParams(), zetherStatement, zetherWitness);

        System.out.println("bTransfer: " + bTransfer);
        System.out.println("bDiff: " + new BigInteger(1, bDiffBytes));
        System.out.println("CLn: " + balanceCommitNewL);
        System.out.println("CRn: " + balanceCommitNewR);
        System.out.println("proof length(byte): " + zetherProof.serialize().length);
        return zetherProof.serialize();

    }

    public byte[] proveBurn(byte[] CL, byte[] CR, byte[] yBytes, byte[] bTransferBytes, byte[] gEpochBytes, byte[] xBytes, byte[] bDiff) {
        // again, the contract will immediately roll over, so must fold in STALE pendings

        BN128Point g = Params.burnGenerator();
        BigInteger bTransfer = new BigInteger(1, bTransferBytes);
        BN128Point y = BN128Point.unserialize(yBytes);

        BN128Point balanceCommitNewL = BN128Point.unserialize(CL).subtract(g.multiply(bTransfer));
        BN128Point balanceCommitNewR = BN128Point.unserialize(CR);

        BigInteger x = new BigInteger(1, xBytes);
        BN128Point gEpoch = BN128Point.unserialize(gEpochBytes);
        BN128Point u = gEpoch.multiply(x);

        BurnStatement<BN128Point> burnStatement = new BurnStatement<>(balanceCommitNewL, balanceCommitNewR, y, bTransfer, gEpoch, u);
        BurnWitness burnWitness = new BurnWitness(x, new BigInteger(1, bDiff));
        BurnProof<BN128Point> burnProof = burnProver.generateProof(Params.getBurnParams(), burnStatement, burnWitness);

        System.out.println("CLn: " + balanceCommitNewL);
        System.out.println("CLR: " + balanceCommitNewR);
        System.out.println("proof length(byte): " + burnProof.serialize().length);
        return burnProof.serialize();

    }
}

