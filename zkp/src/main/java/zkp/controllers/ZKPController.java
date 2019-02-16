package zkp.controllers;

import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import zkp.utilities.Prover;
import zkp.utilities.Util;
import zkp.utilities.Verifier;

@RestController
public class ZKPController {

    private Prover prover = new Prover();
    private Verifier verifier = new Verifier();

    @RequestMapping("/prove-transfer")
    String proveTransfer(@RequestParam("CL") String CL, @RequestParam("CR") String CR, @RequestParam("y") String y, @RequestParam("yBar") String yBar, @RequestParam("x") String x, @RequestParam("r") String r, @RequestParam("bTransfer") String bTransfer, @RequestParam("bDiff") String bDiff){
        System.out.println("prove transfer");
        System.out.println("CL: " + CL);
        System.out.println("CR: " + CR);
        System.out.println("y: " + y);
        System.out.println("yBar: " + yBar);
        System.out.println("x: " + x);
        System.out.println("r: " + r);
        System.out.println("bTransfer: " + bTransfer);
        System.out.println("bDiff: " + bDiff);
        return Util.bytesToHex(prover.proveTransfer(
            Util.hexStringToByteArray(CL), Util.hexStringToByteArray(CR),
            Util.hexStringToByteArray(y), Util.hexStringToByteArray(yBar),
            Util.hexStringToByteArray(x), Util.hexStringToByteArray(r),
            Util.hexStringToByteArray(bTransfer), Util.hexStringToByteArray(bDiff)
        ));
    }

    @RequestMapping("/prove-burn")
    String proveBurn(@RequestParam("CL") String CL, @RequestParam("CR") String CR, @RequestParam("y") String y, @RequestParam("bTransfer") String bTransfer, @RequestParam("x") String x, @RequestParam("bDiff") String bDiff){
        System.out.println("prove burn");
        System.out.println("CL: " + CL);
        System.out.println("CR: " + CR);
        System.out.println("y: " + y);
        System.out.println("x: " + x);
        System.out.println("bTransfer: " + bTransfer);
        System.out.println("bDiff: " + bDiff);
        return Util.bytesToHex(prover.proveBurn(
                Util.hexStringToByteArray(CL), Util.hexStringToByteArray(CR),
                Util.hexStringToByteArray(y), Util.hexStringToByteArray(bTransfer),
                Util.hexStringToByteArray(x), Util.hexStringToByteArray(bDiff)
        ));
    }

    @RequestMapping("/verify-proof")
    String verifyProof(@RequestParam("CLn") String CLn, @RequestParam("CRn") String CRn, @RequestParam("inL") String inL, @RequestParam("outL") String outL, @RequestParam("inOutR") String inOutR, @RequestParam("y") String y, @RequestParam("yBar") String yBar, @RequestParam("proof") String proof){
        System.out.println("verify proof");
        return Util.bytesToHex(verifier.verifyTransfer(
                Util.hexStringToByteArray(CLn), Util.hexStringToByteArray(CRn),
                Util.hexStringToByteArray(inL), Util.hexStringToByteArray(outL),
                Util.hexStringToByteArray(inOutR), Util.hexStringToByteArray(y),
                Util.hexStringToByteArray(yBar), Util.hexStringToByteArray(proof)
        ));
    }

    @RequestMapping("/verify-burn")
    String verifyBurn(@RequestParam("CLn") String CLn, @RequestParam("CRn") String CRn, @RequestParam("y") String y, @RequestParam("bTransfer") String bTransfer, @RequestParam("proof") String proof){
        System.out.println("verify burn");
        return Util.bytesToHex(verifier.verifyBurn(
                Util.hexStringToByteArray(CLn), Util.hexStringToByteArray(CRn),
                Util.hexStringToByteArray(y), Util.hexStringToByteArray(bTransfer),
                Util.hexStringToByteArray(proof)
        ));
    }

}
