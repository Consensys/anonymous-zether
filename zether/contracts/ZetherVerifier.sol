pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "./alt_bn128.sol";

contract ZetherVerifier {
    using alt_bn128 for uint256;
    using alt_bn128 for alt_bn128.G1Point;

    uint256 public constant m = 64;
    uint256 public constant n = 6;

    alt_bn128.G1Point[m] public gs;
    alt_bn128.G1Point[m] public hs;
    alt_bn128.G1Point public pedersenBaseG;
    alt_bn128.G1Point public pedersenBaseH;

    uint256[m] internal twos = powers(2);

    struct ZetherProof {
        alt_bn128.G1Point A;
        alt_bn128.G1Point S;
        alt_bn128.G1Point[2] commits;
        uint256 tauX;
        uint256 mu;
        uint256 t;
        AnonProof anonProof;
        SigmaProof sigmaProof;
        InnerProductProof ipProof;
    }

    struct AnonProof {
        alt_bn128.G1Point A;
        alt_bn128.G1Point B;
        alt_bn128.G1Point C;
        alt_bn128.G1Point D;
        alt_bn128.G1Point[][2] LG; // not storing size as a member.
        alt_bn128.G1Point RG;
        alt_bn128.G1Point balanceCommitNewLG;
        alt_bn128.G1Point balanceCommitNewRG;
        alt_bn128.G1Point[][2] yG; // assuming this one has the same size..., N / 2 by 2,
        alt_bn128.G1Point parityG0;
        alt_bn128.G1Point parityG1;
        uint256[][2] f; // and that this has size N - 1 by 2.
        uint256 zA;
        uint256 zC;
    }

    struct SigmaProof {
        uint256 c;
        uint256 sX;
        uint256 sR;
    }

    struct InnerProductProof {
        alt_bn128.G1Point[n] ls;
        alt_bn128.G1Point[n] rs;
        uint256 a;
        uint256 b;
    }

    constructor() public {
        pedersenBaseG = alt_bn128.mapInto("G");
        pedersenBaseH = alt_bn128.mapInto("H");
        for (uint8 i = 0; i < m; i++) {
            gs[i] = alt_bn128.mapInto("G", i);
            hs[i] = alt_bn128.mapInto("H", i);
        }
    }

    struct Board {
        uint256 y;
        uint256[m] ys;
        uint256 z;
        uint256 zSquared;
        uint256 zCubed;
        uint256[m] twoTimesZSquared;
        uint256 x;
        alt_bn128.G1Point lhs;
        uint256 k;
        alt_bn128.G1Point rhs;
        uint256 uChallenge;
        alt_bn128.G1Point u;
        alt_bn128.G1Point P;
    }

    function verify(bytes32[2][] calldata CL, bytes32[2][] calldata CR, bytes32[2][] calldata L, bytes32[2] calldata R, bytes32[2][] calldata y, uint256 epoch, bytes32[2] calldata u, bytes calldata proof) pure external returns (bool) {
        ZetherProof memory zetherProof = unserialize(proof); // will include the ipproof internally
        Board memory b;
        b.y = uint256(keccak256(abi.encode(input.X, input.Y, proof.A.X, proof.A.Y, proof.S.X, proof.S.Y))).mod();
        // ^^^ not sure what "input" meant in the original parameter list.
        // either way, this will need to be made to incorporate the full parameters of the statement, a la lines 48 to 52 of ZetherVerifier.
        b.ys = powers(b.y);
        b.z = uint256(keccak256(abi.encode(b.y))).mod();
        b.zSquared = b.z.mul(b.z);
        b.zCubed = b.zSquared.mul(b.z);
        b.twoTimesZSquared = times(twos, b.zSquared);
        b.x = uint256(keccak256(abi.encode(proof.commits[0].X, proof.commits[0].Y, proof.commits[1].X, proof.commits[1].Y))).mod();
        b.lhs = pedersenBaseG.mul(proof.t).add(pedersenBaseH.mul(proof.tauX));
        uint256 zSum = b.zSquared.add(b.zCubed).multiply(b.z);
        b.k = sumScalars(b.ys).mul(b.z.sub(b.zSquared)).sub(zSum.mul(2 ** m).sub(zSum));
        b.rhs = proof.commits[0].mul(b.x).add(proof.commits[1].mul(b.x.mul(b.x)));
        b.rhs = b.rhs.add(input.mul(b.zSquared));
        b.rhs = b.rhs.add(pedersenBaseG.mul(b.k));
        if (!b.rhs.eq(b.lhs)) {
            return false;
        }
        b.uChallenge = uint256(keccak256(abi.encode(proof.tauX, proof.mu, proof.t))).mod();
        // why isn't the challenge x passed in?!? should include it in future hashes (fiat shamir).
        // when i'm done, actually it won't be x, but rather the challenge from the sigma protocol.
        // x will go into the anon proof.
        b.u = pedersenBaseG.mul(b.uChallenge);
        alt_bn128.G1Point[m] memory hPrimes = hadamard_inv(hs, b.ys);
        uint256[m] memory hExp = addVectors(times(b.ys, b.z), b.twoTimesZSquared);
        b.P = proof.A.add(proof.S.mul(b.x));
        b.P = b.P.add(sumPoints(gs).mul(b.z.neg()));
        b.P = b.P.add(commit(hPrimes, hExp));
        b.P = b.P.add(pedersenBaseH.mul(proof.mu).neg());
        b.P = b.P.add(b.u.mul(proof.t));
        return ipVerifier.verifyWithCustomParams(b.P, toXs(proof.ipProof.ls), toYs(proof.ipProof.ls), toXs(proof.ipProof.rs), toYs(proof.ipProof.rs), proof.ipProof.a, proof.ipProof.b, hPrimes, b.u);
    }
    
        struct Board {
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

    function verifyIP(uint256 salt, InnerProductProof calldata proof) external view returns (bool) {
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

    function unserialize(bytes memory proof) internal pure returns (ZetherProof memory) {
        /// todo
    }

    function addVectors(uint256[m] memory a, uint256[m] memory b) internal pure returns (uint256[m] memory result) {
        for (uint8 i = 0; i < m; i++) {
            result[i] = a[i].add(b[i]);
        }
    }

    function hadamard_inv(alt_bn128.G1Point[m] memory ps, uint256[m] memory ss) internal view returns (alt_bn128.G1Point[m] memory result) {
        for (uint8 i = 0; i < m; i++) {
            result[i] = ps[i].mul(ss[i].inv());
        }
    }

    function sumScalars(uint256[m] memory ys) internal pure returns (uint256 result) {
        for (uint8 i = 0; i < m; i++) {
            result = result.add(ys[i]);
        }
    }

    function sumPoints(alt_bn128.G1Point[m] memory ps) internal view returns (alt_bn128.G1Point memory sum) {
        sum = ps[0];
        for (uint8 i = 1; i < m; i++) {
            sum = sum.add(ps[i]);
        }
    }

    function commit(alt_bn128.G1Point[m] memory ps, uint256[m] memory ss) internal view returns (alt_bn128.G1Point memory commit) {
        commit = ps[0].mul(ss[0]);
        for (uint8 i = 1; i < m; i++) {
            commit = commit.add(ps[i].mul(ss[i]));
        }
    }

    function toXs(alt_bn128.G1Point[n] memory ps) internal pure returns (uint256[n] memory xs) {
        for (uint8 i = 0; i < n; i++) {
            xs[i] = ps[i].X;
        }
    }

    function toYs(alt_bn128.G1Point[n] memory ps) internal pure returns (uint256[n] memory ys) {
        for (uint8 i = 0; i < n; i++) {
            ys[i] = ps[i].Y;
        }
    }

    function powers(uint256 base) internal pure returns (uint256[m] memory powers) {
        powers[0] = 1;
        powers[1] = base;
        for (uint8 i = 2; i < m; i++) {
            powers[i] = powers[i-1].mul(base);
        }
    }

    function times(uint256[m] memory v, uint256 x) internal pure returns (uint256[m] memory result) {
        for (uint8 i = 0; i < m; i++) {
            result[i] = v[i].mul(x);
        }
    }
}
