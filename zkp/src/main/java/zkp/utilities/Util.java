package zkp.utilities;

public class Util {

    private final static char[] hexArray = "0123456789ABCDEF".toCharArray();

    public static byte[] hexStringToByteArray(String s) {
        s = s.substring(2).toUpperCase();
        int len = s.length();
        if (len % 2 == 1){
            len++;
            s = "0" + s;
        }
        byte[] data = new byte[len / 2];
        for (int i = 0; i < len; i += 2) {
            data[i / 2] = (byte) ((Character.digit(s.charAt(i), 16) << 4)
                    + Character.digit(s.charAt(i+1), 16));
        }
        return data;
    }


    public static byte[][] hexStringsToByteArray(String s) { // assumes that s is 0x + a concatenation of 64-byte hex strings!
        s = s.substring(2).toUpperCase();
        int size = s.length() / 64;
        byte[][] data = new byte[64][size];
        for (int i = 0; i < size; i++) {
            data[i] = hexStringToByteArray(s.substring(i * 64, (i + 1) * 64));
        }
        return data;
    }

    public static String bytesToHex(byte[] bytes) {
        char[] hexChars = new char[bytes.length * 2 + 2];
        hexChars[0] = '0';
        hexChars[1] = 'x';
        for ( int j = 0; j < bytes.length; j++ ) {
            int v = bytes[j] & 0xFF;
            hexChars[j * 2 + 2] = hexArray[v >>> 4];
            hexChars[j * 2 + 3] = hexArray[v & 0x0F];
        }
        return new String(hexChars);
    }

}
