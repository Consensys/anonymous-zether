pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "./alt_bn128.sol";

contract BurnVerifier {
    using alt_bn128 for uint256;
    using alt_bn128 for alt_bn128.G1Point;

    uint256 constant m = 32;
    uint256 constant n = 5;

    alt_bn128.G1Point[m] gs;
    alt_bn128.G1Point[m] hs;
    alt_bn128.G1Point g;
    alt_bn128.G1Point h;

    uint256[m] twos = powers(2); // how much is this actually used?

    struct BurnStatement {
        alt_bn128.G1Point balanceCommitNewL;
        alt_bn128.G1Point balanceCommitNewR;
        alt_bn128.G1Point y;
        uint256 bTransfer;
        uint256 epoch; // or uint8?
        alt_bn128.G1Point u;
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

    constructor() public {
        g = alt_bn128.mapInto("G");
        h = alt_bn128.mapInto("H");
        for (uint8 i = 0; i < m; i++) {
            gs[i] = alt_bn128.mapInto("G", i);
            hs[i] = alt_bn128.mapInto("H", i);
        }
    } // will it be more expensive later on to sload these than to recompute them?

    function verify(bytes32[2] memory CLn, bytes32[2] memory CRn, bytes32[2] memory y, uint256 bTransfer, uint256 epoch, bytes32[2] memory u, bytes memory proof) view public returns (bool) {
        BurnStatement memory statement; // WARNING: if this is called directly in the console,
        // and your strings are less than 64 characters, they will be padded on the right, not the left. should hopefully not be an issue,
        // as this will typically be called simply by the other contract, which will get its arguments using precompiles. still though, beware
        statement.balanceCommitNewL = alt_bn128.G1Point(uint256(CLn[0]), uint256(CLn[1]));
        statement.balanceCommitNewR = alt_bn128.G1Point(uint256(CRn[0]), uint256(CRn[1]));
        statement.y = alt_bn128.G1Point(uint256(y[0]), uint256(y[1]));
        statement.bTransfer = bTransfer;
        statement.epoch = epoch;
        statement.u = alt_bn128.G1Point(uint256(u[0]), uint256(u[1]));
        BurnProof memory burnProof = unserialize(proof);
        return verifyBurn(statement, burnProof);
    }

    struct BurnAuxiliaries {
        uint256 y;
        uint256[m] ys;
        uint256 z;
        uint256 zSquared;
        uint256 zCubed;
        uint256[m] twoTimesZSquared;
        uint256 k;
        alt_bn128.G1Point tEval;
        uint256 t;
        uint256 x;
    }

    struct SigmaAuxiliaries {
        uint256 minusC;
        alt_bn128.G1Point Ay;
        alt_bn128.G1Point gEpoch;
        alt_bn128.G1Point Au;
        alt_bn128.G1Point cCommit;
        alt_bn128.G1Point At;
    }

    function verifyBurn(BurnStatement memory statement, BurnProof memory proof) view internal returns (bool) {
        BurnAuxiliaries memory burnAuxiliaries;
        burnAuxiliaries.y = uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(statement.bTransfer, statement.epoch, statement.y, statement.balanceCommitNewL, statement.balanceCommitNewR))).mod(), proof.A, proof.S))).mod();
        burnAuxiliaries.ys = powers(burnAuxiliaries.y);
        burnAuxiliaries.z = uint256(keccak256(abi.encode(burnAuxiliaries.y))).mod();
        burnAuxiliaries.zSquared = burnAuxiliaries.z.mul(burnAuxiliaries.z);
        burnAuxiliaries.zCubed = burnAuxiliaries.zSquared.mul(burnAuxiliaries.z);
        burnAuxiliaries.twoTimesZSquared = times(twos, burnAuxiliaries.zSquared);
        burnAuxiliaries.x = uint256(keccak256(abi.encode(burnAuxiliaries.z, proof.commits))).mod();

        // begin verification of sigma proof. is it worth passing to a different method?
        burnAuxiliaries.k = sumScalars(burnAuxiliaries.ys).mul(burnAuxiliaries.z.sub(burnAuxiliaries.zSquared)).sub(burnAuxiliaries.zCubed.mul(2 ** m).sub(burnAuxiliaries.zCubed)); // really care about t - k
        burnAuxiliaries.tEval = proof.commits[0].mul(burnAuxiliaries.x).add(proof.commits[1].mul(burnAuxiliaries.x.mul(burnAuxiliaries.x))); // replace with "commit"?
        burnAuxiliaries.t = proof.t.sub(burnAuxiliaries.k);

        SigmaAuxiliaries memory sigmaAuxiliaries;
        sigmaAuxiliaries.minusC = proof.sigmaProof.c.neg();
        sigmaAuxiliaries.Ay = g.mul(proof.sigmaProof.sX).add(statement.y.mul(sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.gEpoch = alt_bn128.mapInto("Zether", statement.epoch);
        sigmaAuxiliaries.Au = sigmaAuxiliaries.gEpoch.mul(proof.sigmaProof.sX).add(statement.u.mul(sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.cCommit = statement.balanceCommitNewL.mul(proof.sigmaProof.c.mul(burnAuxiliaries.zSquared)).add(statement.balanceCommitNewR.mul(proof.sigmaProof.sX.mul(burnAuxiliaries.zSquared))).neg();
        sigmaAuxiliaries.At = g.mul(burnAuxiliaries.t.mul(proof.sigmaProof.c)).add(h.mul(proof.tauX.mul(proof.sigmaProof.c))).add(sigmaAuxiliaries.cCommit.add(burnAuxiliaries.tEval.mul(proof.sigmaProof.c)).neg());

        uint256 challenge = uint256(keccak256(abi.encode(burnAuxiliaries.x, sigmaAuxiliaries.Ay, sigmaAuxiliaries.Au, sigmaAuxiliaries.At))).mod();
        require(challenge == proof.sigmaProof.c, "Sigma protocol challenge equality failure.");

        uint256 uChallenge = uint256(keccak256(abi.encode(proof.sigmaProof.c, proof.t, proof.tauX, proof.mu))).mod();
        alt_bn128.G1Point memory u = g.mul(uChallenge);
        alt_bn128.G1Point[m] memory hPrimes = hadamard_inv(hs, burnAuxiliaries.ys);
        uint256[m] memory hExp = addVectors(times(burnAuxiliaries.ys, burnAuxiliaries.z), burnAuxiliaries.twoTimesZSquared);
        alt_bn128.G1Point memory P = proof.A.add(proof.S.mul(burnAuxiliaries.x));
        P = P.add(sumPoints(gs).mul(burnAuxiliaries.z.neg()));
        P = P.add(commit(hPrimes, hExp)).add(h.mul(proof.mu).neg()).add(u.mul(proof.t));

        // begin inner product verification
        InnerProductProof memory ipProof = proof.ipProof;
        uint256[n] memory challenges;
        for (uint8 i = 0; i < n; i++) {
            uChallenge = uint256(keccak256(abi.encode(uChallenge, ipProof.ls[i], ipProof.rs[i]))).mod();
            challenges[i] = uChallenge;
            uint256 xInv = uChallenge.inv();
            P = ipProof.ls[i].mul(uChallenge.exp(2)).add(ipProof.rs[i].mul(xInv.exp(2))).add(P);
        }

        uint256[m] memory otherExponents;
        otherExponents[0] = challenges[0];
        for (uint8 i = 1; i < n; i++) {
            otherExponents[0] = otherExponents[0].mul(challenges[i]);
        }
        bool[m] memory bitSet;
        otherExponents[0] = otherExponents[0].inv();
        for (uint8 i = 0; i < m/2; ++i) {
            for (uint8 j = 0; (1 << j) + i < m; ++j) {
                uint8 i1 = i + (1 << j);
                if (!bitSet[i1]) {
                    uint256 temp = challenges[n-1-j].mul(challenges[n-1-j]);
                    otherExponents[i1] = otherExponents[i].mul(temp);
                    bitSet[i1] = true;
                }
            }
        }

        alt_bn128.G1Point memory gTemp = multiExpGs(otherExponents);
        alt_bn128.G1Point memory hTemp = multiExpHsInversed(otherExponents, hs);
        alt_bn128.G1Point memory cProof = gTemp.mul(ipProof.a).add(hTemp.mul(ipProof.b)).add(h.mul(ipProof.a.mul(ipProof.b)));
        require(P.eq(cProof), "Inner product equality check failure.");
        return true;
    }

    function multiExpGs(uint256[m] memory ss) internal view returns (alt_bn128.G1Point memory g) {
        for (uint8 i = 0; i < m; i++) {
            g = g.add(gs[i].mul(ss[i]));
        }
    }

    function multiExpHsInversed(uint256[m] memory ss, alt_bn128.G1Point[m] memory hs) internal view returns (alt_bn128.G1Point memory h) {
        for (uint8 i = 0; i < m; i++) {
            h = h.add(hs[i].mul(ss[m-1-i]));
        }
    }
    
    // begin util functions

    function unserialize(bytes memory arr) internal pure returns (BurnProof memory) {
        BurnProof memory proof;
        proof.A = alt_bn128.G1Point(slice(arr, 0), slice(arr, 32));
        proof.S = alt_bn128.G1Point(slice(arr, 64), slice(arr, 96));
        proof.commits = [alt_bn128.G1Point(slice(arr, 128), slice(arr, 160)), alt_bn128.G1Point(slice(arr, 192), slice(arr, 224))];
        proof.t = slice(arr, 256);
        proof.tauX = slice(arr, 288);
        proof.mu = slice(arr, 320);

        SigmaProof memory sigmaProof;
        sigmaProof.c = slice(arr, 352);
        sigmaProof.sX = slice(arr, 384);
        proof.sigmaProof = sigmaProof;

        InnerProductProof memory ipProof;
        for (uint8 i = 0; i < n; i++) {
            ipProof.ls[i] = alt_bn128.G1Point(slice(arr, 416 + i * 64), slice(arr, 448 + i * 64));
            ipProof.rs[i] = alt_bn128.G1Point(slice(arr, 416 + (n + i) * 64), slice(arr, 448 + (n + i) * 64));
        }
        proof.ipProof = ipProof;
        return proof;
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
        for (uint8 i = 0; i < m; i++) {
            sum = sum.add(ps[i]);
        }
    }

    function commit(alt_bn128.G1Point[m] memory ps, uint256[m] memory ss) internal view returns (alt_bn128.G1Point memory result) {
        for (uint8 i = 0; i < m; i++) {
            result = result.add(ps[i].mul(ss[i]));
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

    function slice(bytes memory input, uint256 start) internal pure returns (uint256 result) { // extracts exactly 32 bytes
        assembly {
            let m := mload(0x40)
            mstore(m, mload(add(add(input, 0x20), start))) // why only 0x20?
            result := mload(m)
        }
    }
}
