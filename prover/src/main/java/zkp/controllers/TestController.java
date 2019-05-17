package zkp.controllers;

import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import zkp.utilities.Util;

@RestController
public class TestController {

    @RequestMapping("/test")
    String add(@RequestParam("a") String a, @RequestParam("b") String b) {
        System.out.println("a: " + a);
        System.out.println("b: " + b);
        byte[] r = Util.hexStringToByteArray(a);
        System.out.println("length: " + r.length);
        r[r.length - 1] = (byte)255;
        System.out.println("return: " + Util.bytesToHex(r));
        return Util.bytesToHex(r);
    }

    @RequestMapping("/test-precompile")
    boolean test(@RequestParam("input") String input) {
        System.out.println("input: " + input);
        byte[] r = Util.hexStringToByteArray(input);
        System.out.println("length: " + r.length);
        return true;
    }

}
