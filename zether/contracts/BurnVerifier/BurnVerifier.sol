pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "./SigmaVerifier.sol";
import "./IPVerifier.sol";
import "../alt_bn128.sol";

contract BurnVerifier {
    using alt_bn128 for uint256;
    using alt_bn128 for alt_bn128.G1Point;

    uint256 public constant m = 32;
    uint256 public constant n = 5;

    alt_bn128.G1Point[m] public gs;
    alt_bn128.G1Point[m] public hs;
    alt_bn128.G1Point public pedersenBaseG;
    alt_bn128.G1Point public pedersenBaseH;

    uint256[m] internal twos = powers(2);

    SigmaBurnVerifier sigmaVerifier = new SigmaBurnVerifier();
    BurnIPVerifier ipVerifier = new BurnIPVerifier();

    constructor() public {
        pedersenBaseG = alt_bn128.mapInto("G");
        pedersenBaseH = alt_bn128.mapInto("H");
        for (uint8 i = 0; i < m; i++) {
            gs[i] = alt_bn128.mapInto("G", i);
            hs[i] = alt_bn128.mapInto("H", i);
        }
    }

    struct BurnProof {
        alt_bn128.G1Point A;
        alt_bn128.G1Point S;
        alt_bn128.G1Point[2] commits;
        uint256 tauX;
        uint256 mu;
        uint256 t;
        SigmaProof sigmaProof;
        InnerProductProof ipProof;
    }

    struct SigmaProof {
        uint256 c;
        uint256 sX;
    }

    struct InnerProductProof {
        alt_bn128.G1Point[n] ls;
        alt_bn128.G1Point[n] rs;
        uint256 a;
        uint256 b;
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

    function verify(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata y, uint256 bTransfer, uint256 epoch, bytes32[2] calldata u, bytes calldata proof) pure external returns (bool) {
    // will need to slice everything internally.
    //     // alternatively: could return _individual_ components of the proof from go, and then pass them individually using web3 / solidity typing.
    //     uint256[10] calldata coords, // [input_x, input_y, A_x, A_y, S_x, S_y, commits[0]_x, commits[0]_y, commits[1]_x, commits[1]_y]
    //     uint256[5] calldata scalars, // [tauX, mu, t, a, b]
    //     uint256[] calldata ls_coords, // 2 * n
    //     uint256[] calldata rs_coords  // 2 * n
    // ) external view returns (bool) {
        BurnProof memory burnProof = unserialize(proof); // will include the ipproof internally

        Board memory b;
        b.y = uint256(keccak256(abi.encode(input.X, input.Y, proof.A.X, proof.A.Y, proof.S.X, proof.S.Y))).mod();
        b.ys = powers(b.y);
        b.z = uint256(keccak256(abi.encode(b.y))).mod();
        b.zSquared = b.z.mul(b.z);
        b.zCubed = b.zSquared.mul(b.z);
        b.twoTimesZSquared = times(twos, b.zSquared);
        b.x = uint256(keccak256(abi.encode(proof.commits[0].X, proof.commits[0].Y, proof.commits[1].X, proof.commits[1].Y))).mod();
        b.lhs = pedersenBaseG.mul(proof.t).add(pedersenBaseH.mul(proof.tauX));
        b.k = sumScalars(b.ys).mul(b.z.sub(b.zSquared)).sub(b.zCubed.mul(2 ** m).sub(b.zCubed));
        b.rhs = proof.commits[0].mul(b.x).add(proof.commits[1].mul(b.x.mul(b.x)));
        b.rhs = b.rhs.add(input.mul(b.zSquared));
        b.rhs = b.rhs.add(pedersenBaseG.mul(b.k));
        if (!b.rhs.eq(b.lhs)) {
            return false;
        }
        b.uChallenge = uint256(keccak256(abi.encode(proof.tauX, proof.mu, proof.t))).mod();
        // ^^^ why isn't the challenge x passed in?!? should include it in future hashes (fiat shamir).
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

    function unserialize(bytes memory proof) internal pure returns (BurnProof memory) {
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
