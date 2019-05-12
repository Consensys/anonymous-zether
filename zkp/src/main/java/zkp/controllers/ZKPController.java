package zkp.controllers;

import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import zkp.utilities.Prover;
import zkp.utilities.Util;
import zkp.utilities.Verifier;

import javax.annotation.PostConstruct;
import java.math.BigInteger;

@RestController
public class ZKPController {

    private Prover prover = new Prover();
    private Verifier verifier = new Verifier();

    @PostConstruct
    public void init() {
        byte[][] empty = new byte[2][64];
        prover.proveTransfer(empty, empty, empty, new byte[32], new byte[32], new byte[32], new byte[32], new byte[32], empty);
        // horrific hack, to force classes to load...
    }

    @RequestMapping("/prove-transfer")
    String proveTransfer(@RequestParam("CL") String CL, @RequestParam("CR") String CR, @RequestParam("y") String y, @RequestParam("epoch") String epoch, @RequestParam("x") String x, @RequestParam("r") String r, @RequestParam("bTransfer") String bTransfer, @RequestParam("bDiff") String bDiff, @RequestParam("outIndex") String outIndex, @RequestParam("inIndex") String inIndex) {
        System.out.println("prove transfer");
        System.out.println("CL: " + CL);
        System.out.println("CR: " + CR);
        System.out.println("y: " + y);
        System.out.println("epoch: " + epoch);
        System.out.println("x: " + x);
        System.out.println("r: " + r);
        System.out.println("bTransfer: " + bTransfer);
        System.out.println("bDiff: " + bDiff);
        System.out.println("indexes: " + outIndex + ", " + inIndex);
        String proof = Util.bytesToHex(prover.proveTransfer(
                Util.hexStringsToByteArrays(CL),
                Util.hexStringsToByteArrays(CR),
                Util.hexStringsToByteArrays(y),
                Util.hexStringToByteArray(epoch), // let's pass this as a padded, 32-byte (hex) integer.
                Util.hexStringToByteArray(x),
                Util.hexStringToByteArray(r),
                Util.hexStringToByteArray(bTransfer),
                Util.hexStringToByteArray(bDiff),
                new byte[][]{Util.hexStringToByteArray(outIndex), Util.hexStringToByteArray(inIndex)}));
        System.out.println("proof: " + proof);
        return proof;
    }

    @RequestMapping("/prove-burn")
    String proveBurn(@RequestParam("CL") String CL, @RequestParam("CR") String CR, @RequestParam("y") String y, @RequestParam("bTransfer") String bTransfer, @RequestParam("epoch") String epoch, @RequestParam("x") String x, @RequestParam("bDiff") String bDiff) {
        System.out.println("prove burn");
        System.out.println("CL: " + CL);
        System.out.println("CR: " + CR);
        System.out.println("y: " + y);
        System.out.println("epoch: " + epoch);
        System.out.println("x: " + x);
        System.out.println("bTransfer: " + bTransfer);
        System.out.println("bDiff: " + bDiff);
        String proof = Util.bytesToHex(prover.proveBurn(
                Util.hexStringToByteArray(CL),
                Util.hexStringToByteArray(CR),
                Util.hexStringToByteArray(y),
                Util.hexStringToByteArray(bTransfer),
                Util.hexStringToByteArray(epoch), // let's pass this as a padded, 32-byte (hex) integer.
                Util.hexStringToByteArray(x),
                Util.hexStringToByteArray(bDiff)
        ));
        System.out.println("proof: " + proof);
        return proof;
    }

    @RequestMapping("/gEpoch")
    String proveBurn(@RequestParam("epoch") String epoch) {
        System.out.println("epoch: " + epoch);
        String gEpoch = Util.bytesToHex(prover.gEpochGenerator(
                Util.hexStringToByteArray(epoch) // let's pass this as a padded, 32-byte (hex) integer.
        ));
        System.out.println("gEpoch: " + gEpoch);
        return gEpoch;
    }

    @RequestMapping("/verify-transfer")
    boolean verifyTransfer(@RequestParam("input") String input) {
        System.out.println("verify transfer");
        int size = new BigInteger(input.substring(650, 714), 16).intValue(); // CL's length is between bytes 0x144 and 0x164.
        String CLn = "0x" + input.substring(714, 714 + size * 128); // bytes 0x164 to 0x162 + 0x40 * size
        String CRn = "0x" + input.substring(778 + size * 128, 778 + 2 * size * 128); // 0x164 + 0x40 * size + 0x20 length header
        String L = "0x" + input.substring(842 + 2 * size * 128, 842 + 3 * size * 128); // etc.
        String R = "0x" + input.substring(202, 330);
        String y = "0x" + input.substring(906 + 3 * size * 128, 906 + 4 * size * 128);
        String epoch = "0x" + input.substring(394, 458);
        String u = "0x" + input.substring(458, 586);
        String proof = "0x" + input.substring(970 + 4 * size * 128); // not checking length
        System.out.println("CL: " + CLn);
        System.out.println("CR: " + CRn);
        System.out.println("L: " + L);
        System.out.println("R: " + R);
        System.out.println("y: " + y);
        System.out.println("epoch: " + epoch);
        System.out.println("u: " + u);
        System.out.println("proof: " + proof);
        boolean isValid = verifier.verifyTransfer(
                Util.hexStringsToByteArrays(CLn),
                Util.hexStringsToByteArrays(CRn),
                Util.hexStringsToByteArrays(L),
                Util.hexStringToByteArray(R),
                Util.hexStringsToByteArrays(y),
                Util.hexStringToByteArray(epoch),
                Util.hexStringToByteArray(u),
                Util.hexStringToByteArray(proof)
        );
        System.out.println(" >>>>> " + isValid);
        return isValid;
    }

    @RequestMapping("/verify-burn")
    boolean verifyBurn(@RequestParam("input") String input) {
        System.out.println("verify burn");
        String CLn = "0x" + input.substring(10, 138);
        String CRn = "0x" + input.substring(138, 266);
        String y = "0x" + input.substring(266, 394);
        String bTransfer = "0x" + input.substring(394, 458);
        String epoch = "0x" + input.substring(458, 522);
        String u = "0x" + input.substring(522, 650);
        // need to skip both the pointer to the beginning of proof (32 bytes) and its length (32 bytes)
        String proof = "0x" + input.substring(778);
        System.out.println("CLn: " + CLn);
        System.out.println("CRn: " + CRn);
        System.out.println("y: " + y);
        System.out.println("bTransfer: " + bTransfer);
        System.out.println("epoch: " + epoch);
        System.out.println("u: " + u);
        System.out.println("proof: " + proof);
        boolean isValid = verifier.verifyBurn(
                Util.hexStringToByteArray(CLn),
                Util.hexStringToByteArray(CRn),
                Util.hexStringToByteArray(y),
                Util.hexStringToByteArray(bTransfer),
                Util.hexStringToByteArray(epoch),
                Util.hexStringToByteArray(u),
                Util.hexStringToByteArray(proof)
        );
        System.out.println(" >>>>> " + isValid);
        return isValid;
    }

}
