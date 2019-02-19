package zkp.utilities;

import edu.stanford.cs.crypto.efficientct.VerificationFailedException;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Point;
import edu.stanford.cs.crypto.efficientct.burnprover.*;
import edu.stanford.cs.crypto.efficientct.zetherprover.*;

import java.math.BigInteger;

public class Verifier {

    private ZetherVerifier<BN128Point> zetherVerifier = new ZetherVerifier<>();
    private BurnVerifier<BN128Point> burnVerifier = new BurnVerifier<>();

    public boolean verifyTransfer(byte[] CLn, byte[] CRn, byte[] outL, byte[] inL, byte[] inOutR, byte[] y, byte[] yBar, byte[] proof) {
        ZetherStatement<BN128Point> zetherStatement = new ZetherStatement<>(BN128Point.unserialize(CLn), BN128Point.unserialize(CRn), BN128Point.unserialize(outL), BN128Point.unserialize(inL), BN128Point.unserialize(inOutR),  BN128Point.unserialize(y), BN128Point.unserialize(yBar));
        ZetherProof<BN128Point> zetherProof = ZetherProof.unserialize(proof);
        boolean success = true;
        try {
            zetherVerifier.verify(Params.getZetherParams(), zetherStatement, zetherProof);
        } catch (VerificationFailedException e) {
            e.printStackTrace();
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
            burnVerifier.verify(Params.getBurnParams(), burnStatement, burnProof);
        } catch (VerificationFailedException e) {
//            e.printStackTrace();
            success = false;
        }
        return success;
//        byte[] arr = new byte[32];
//        if (success)
//            arr[0] = 1;
//        return arr;
    }
}