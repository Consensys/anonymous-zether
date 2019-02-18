package zkp.utilities;

import edu.stanford.cs.crypto.efficientct.GeneratorParams;
import edu.stanford.cs.crypto.efficientct.VerificationFailedException;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Group;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Point;
import edu.stanford.cs.crypto.efficientct.burnprover.*;
import edu.stanford.cs.crypto.efficientct.zetherprover.*;

import java.math.BigInteger;

public class Verifier {
    private static final BN128Group group = new BN128Group();
    private static final BN128Point g = group.generator();
    private static final BigInteger q = group.groupOrder();
    private static final BigInteger MAX = BigInteger.valueOf(4294967296L); // one less than this, actually...

    private GeneratorParams<BN128Point> zetherParams = GeneratorParams.generateParams(64, group);
    private ZetherVerifier<BN128Point> zetherVerifier = new ZetherVerifier<>();

    private GeneratorParams<BN128Point> burnParams = GeneratorParams.generateParams(32, group);
    private BurnVerifier<BN128Point> burnVerifier = new BurnVerifier<>();
    // revisit if these are necessary

    public boolean verifyTransfer(byte[] CLn, byte[] CRn, byte[] inL, byte[] outL, byte[] inOutR, byte[] y, byte[] yBar, byte[] proof) {
        ZetherStatement<BN128Point> zetherStatement = new ZetherStatement<>(BN128Point.unserialize(CLn), BN128Point.unserialize(CRn), BN128Point.unserialize(inL), BN128Point.unserialize(outL), BN128Point.unserialize(inOutR),  BN128Point.unserialize(y), BN128Point.unserialize(yBar));
        ZetherProof<BN128Point> zetherProof = ZetherProof.unserialize(proof);
        boolean success = true;
        try {
            zetherVerifier.verify(zetherParams, zetherStatement, zetherProof);
        } catch (VerificationFailedException e) {
            success = false;
        }
        return success;
//        byte[] arr = new byte[32];
//        if (success)
//            arr[0] = 1;
//        return arr;
    }

    public boolean verifyBurn(byte[] CLn, byte[] CRn, byte[] y, byte[] bTransfer, byte[] proof) {
        BurnStatement<BN128Point> burnStatement = new BurnStatement<>(BN128Point.unserialize(CLn), BN128Point.unserialize(CRn), BN128Point.unserialize(y), new BigInteger(1, bTransfer));
        BurnProof<BN128Point> burnProof = BurnProof.unserialize(proof);
        boolean success = true;
        try {
            burnVerifier.verify(burnParams, burnStatement, burnProof);
        } catch (VerificationFailedException e) {
            success = false;
        }
        return success;
//        byte[] arr = new byte[32];
//        if (success)
//            arr[0] = 1;
//        return arr;
    }
}