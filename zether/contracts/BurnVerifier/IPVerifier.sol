pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "../alt_bn128.sol";

contract BurnIPVerifier { // made to mimic "EfficientInnerProductVerifier" in BulletProofLib.
    using alt_bn128 for uint256;
    using alt_bn128 for alt_bn128.G1Point;

    uint256 public constant m = 32;
    uint256 public constant n = 5;

    alt_bn128.G1Point[m] public gs;
    alt_bn128.G1Point[m] public hs;
    alt_bn128.G1Point public H = alt_bn128.mapInto("V");

    constructor(
        uint256 H_x,
        uint256 H_y,
        uint256[2 * m] memory gs_coords,
        uint256[2 * m] memory hs_coords
    ) public {
        for (uint8 i = 0; i < m; i++) {
            gs[i] = alt_bn128.mapInto("G", i);
            hs[i] = alt_bn128.mapInto("H", i);
        }
    }

    struct Board {
        alt_bn128.G1Point[m] hs;
        alt_bn128.G1Point H;

        alt_bn128.G1Point c;
        alt_bn128.G1Point l;
        alt_bn128.G1Point r;
        uint256 x;
        uint256 xInv;
        uint256[n] challenges;
        uint256[m] otherExponents;
        alt_bn128.G1Point g;
        alt_bn128.G1Point h;
        uint256 prod;
        alt_bn128.G1Point cProof;
        bool[m] bitSet;
        uint256 z;
    }

    function verify(
        uint256 c_x,
        uint256 c_y,
        uint256[n] calldata ls_x,
        uint256[n] calldata ls_y,
        uint256[n] calldata rs_x,
        uint256[n] calldata rs_y,
        uint256 A,
        uint256 B
    ) external view returns (bool) {
        return verifyWithCustomParams(alt_bn128.G1Point(c_x, c_y), ls_x, ls_y, rs_x, rs_y, A, B, hs, H);
    }

    function verifyWithCustomParams(
        alt_bn128.G1Point memory c,
        uint256[n] memory ls_x,
        uint256[n] memory ls_y,
        uint256[n] memory rs_x,
        uint256[n] memory rs_y,
        uint256 A,
        uint256 B,
        alt_bn128.G1Point[m] memory hs,
        alt_bn128.G1Point memory H
    ) public view returns (bool) {
        Board memory b;
        b.c = c;
        for (uint8 i = 0; i < n; i++) {
            b.l = alt_bn128.G1Point(ls_x[i], ls_y[i]);
            b.r = alt_bn128.G1Point(rs_x[i], rs_y[i]);
            b.x = uint256(keccak256(abi.encode(b.l.X, b.l.Y, b.c.X, b.c.Y, b.r.X, b.r.Y))).mod();
            b.xInv = b.x.inv();
            b.c = b.l.mul(b.x.exp(2))
                .add(b.r.mul(b.xInv.exp(2)))
                .add(b.c);
            b.challenges[i] = b.x;
        }

        b.otherExponents[0] = b.challenges[0];
        for (uint8 i = 1; i < n; i++) {
            b.otherExponents[0] = b.otherExponents[0].mul(b.challenges[i]);
        }
        b.otherExponents[0] = b.otherExponents[0].inv();
        for (uint8 i = 0; i < m/2; ++i) {
            for (uint8 j = 0; (1 << j) + i < m; ++j) {
                uint8 i1 = i + (1 << j);
                if (!b.bitSet[i1]) {
                    b.z = b.challenges[n-1-j].mul(b.challenges[n-1-j]);
                    b.otherExponents[i1] = b.otherExponents[i].mul(b.z);
                    b.bitSet[i1] = true;
                }
            }
        }

        b.g = multiExpGs(b.otherExponents);
        b.h = multiExpHsInversed(b.otherExponents, hs);
        b.prod = A.mul(B);
        b.cProof = b.g.mul(A)
            .add(b.h.mul(B))
            .add(H.mul(b.prod));
        return b.cProof.X == b.c.X && b.cProof.Y == b.c.Y;
    }

    function multiExpGs(uint256[m] memory ss) internal view returns (alt_bn128.G1Point memory g) {
        g = gs[0].mul(ss[0]);
        for (uint8 i = 1; i < m; i++) {
            g = g.add(gs[i].mul(ss[i]));
        }
    }

    function multiExpHsInversed(uint256[m] memory ss, alt_bn128.G1Point[m] memory hs) internal view returns (alt_bn128.G1Point memory h) {
        h = hs[0].mul(ss[m-1]);
        for (uint8 i = 1; i < m; i++) {
            h = h.add(hs[i].mul(ss[m-1-i]));
        }
    }
}
