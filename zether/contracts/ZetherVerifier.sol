pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "./Utils.sol";

contract ZetherVerifier {
    using Utils for uint256;

    uint256 constant m = 64;
    uint256 constant n = 6;
    uint256 public constant ORDER = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    G1Point[m] gs;
    G1Point[m] hs;
    G1Point g;
    G1Point h;

    uint256[m] twos = powers(2);

    struct ZetherStatement {
        G1Point[] CL;
        G1Point[] CR;
        G1Point[] L;
        G1Point R;
        G1Point[] y;
        uint256 epoch; // or uint8?
        G1Point u;
    }

    struct ZetherProof {
        uint256 size; // not strictly necessary, but...?
        G1Point A;
        G1Point S;
        G1Point[2] commits;
        uint256 tauX;
        uint256 mu;
        uint256 t;
        AnonProof anonProof;
        SigmaProof sigmaProof;
        InnerProductProof ipProof;
    }

    struct AnonProof {
        G1Point A;
        G1Point B;
        G1Point C;
        G1Point D;
        G1Point[2][] LG; // flipping the indexing order on this, 'cause...
        G1Point inOutRG;
        G1Point balanceCommitNewLG;
        G1Point balanceCommitNewRG;
        G1Point[2][] yG; // assuming this one has the same size..., N / 2 by 2,
        G1Point parityG0;
        G1Point parityG1;
        uint256[2][] f; // and that this has size N - 1 by 2.
        uint256 zA;
        uint256 zC;
    }

    struct SigmaProof {
        uint256 c;
        uint256 sX;
        uint256 sR;
    }

    struct InnerProductProof {
        G1Point[n] ls;
        G1Point[n] rs;
        uint256 a;
        uint256 b;
    }

    constructor() public {
        g = mapInto("G");
        h = mapInto("V");
        for (uint256 i = 0; i < m; i++) {
            gs[i] = mapInto("G", i);
            hs[i] = mapInto("H", i);
        }
    }

    function verifyTransfer(bytes32[2][] memory CL, bytes32[2][] memory CR, bytes32[2][] memory L, bytes32[2] memory R, bytes32[2][] memory y, uint256 epoch, bytes32[2] memory u, bytes memory proof) view public returns (bool) {
        ZetherStatement memory statement;
        uint256 size = y.length;
        statement.CL = new G1Point[](size);
        statement.CR = new G1Point[](size);
        statement.L = new G1Point[](size);
        statement.y = new G1Point[](size);
        for (uint256 i = 0; i < size; i++) {
            statement.CL[i] = G1Point(uint256(CL[i][0]), uint256(CL[i][1]));
            statement.CR[i] = G1Point(uint256(CR[i][0]), uint256(CR[i][1]));
            statement.L[i] = G1Point(uint256(L[i][0]), uint256(L[i][1]));
            statement.y[i] = G1Point(uint256(y[i][0]), uint256(y[i][1]));
        }
        statement.R = G1Point(uint256(R[0]), uint256(R[1]));
        statement.epoch = epoch;
        statement.u = G1Point(uint256(u[0]), uint256(u[1]));
        ZetherProof memory zetherProof = unserialize(proof);
        return verify(statement, zetherProof);
    }

    struct ZetherAuxiliaries {
        uint256 y;
        uint256[m] ys;
        uint256 z;
        uint256 zSquared;
        uint256 zCubed;
        uint256[m] twoTimesZSquared;
        uint256 k;
        G1Point tEval;
        uint256 t;
        uint256 x;
    }

    struct SigmaAuxiliaries {
        uint256 minusC;
        G1Point[2][] AL;
        G1Point Ay;
        G1Point AD;
        G1Point gEpoch;
        G1Point Au;
        G1Point ADiff;
        G1Point cCommit;
        G1Point At;
    }

    struct AnonAuxiliaries {
        uint256 x;
        uint256[2][] f;
        uint256 xInv;
        G1Point inOutR2;
        G1Point balanceCommitNewL2;
        G1Point balanceCommitNewR2;
        uint256[2][] cycler;
        G1Point[2][] L2;
        G1Point[2][] y2;
        G1Point parity;
        G1Point gPrime;
    }

    struct IPAuxiliaries {
        G1Point u;
        G1Point[m] hPrimes;
        uint256[m] hExp;
        G1Point P;
        uint256 uChallenge;
        uint256[n] challenges;
        uint256[m] otherExponents;
    }

    function verify(ZetherStatement memory statement, ZetherProof memory proof) view internal returns (bool) {
        require(proof.size % 2 == 0, "Anonymity set size must be even!");

        ZetherAuxiliaries memory zetherAuxiliaries;
        zetherAuxiliaries.y = uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(statement.epoch, statement.R, statement.CL, statement.CR, statement.L, statement.y))).mod(), proof.A, proof.S))).mod();
        zetherAuxiliaries.ys = powers(zetherAuxiliaries.y);
        zetherAuxiliaries.z = uint256(keccak256(abi.encode(zetherAuxiliaries.y))).mod();
        zetherAuxiliaries.zSquared = zetherAuxiliaries.z.mul(zetherAuxiliaries.z);
        zetherAuxiliaries.zCubed = zetherAuxiliaries.zSquared.mul(zetherAuxiliaries.z);
        // zetherAuxiliaries.twoTimesZSquared = times(twos, zetherAuxiliaries.zSquared);
        for (uint256 i = 0; i < m / 2; i++) {
            zetherAuxiliaries.twoTimesZSquared[i] = zetherAuxiliaries.zSquared.mul(2 ** i);
            zetherAuxiliaries.twoTimesZSquared[i + m / 2] = zetherAuxiliaries.zCubed.mul(2 ** i);
        }
        zetherAuxiliaries.x = uint256(keccak256(abi.encode(zetherAuxiliaries.z, proof.commits))).mod();

        uint256 zSum = zetherAuxiliaries.zSquared.add(zetherAuxiliaries.zCubed).mul(zetherAuxiliaries.z);
        zetherAuxiliaries.k = sumScalars(zetherAuxiliaries.ys).mul(zetherAuxiliaries.z.sub(zetherAuxiliaries.zSquared)).sub(zSum.mul(2 ** (m / 2)).sub(zSum));
        zetherAuxiliaries.tEval = add(mul(proof.commits[0], zetherAuxiliaries.x), mul(proof.commits[1], zetherAuxiliaries.x.mul(zetherAuxiliaries.x))); // replace with "commit"?
        zetherAuxiliaries.t = proof.t.sub(zetherAuxiliaries.k);

        // begin anon proof.
        // length equality checks for anonProof members? or during deserialization?
        AnonProof memory anonProof = proof.anonProof;
        AnonAuxiliaries memory anonAuxiliaries;
        anonAuxiliaries.x = uint256(keccak256(abi.encode(zetherAuxiliaries.x, anonProof.LG, anonProof.yG, anonProof.A, anonProof.B, anonProof.C, anonProof.D, anonProof.inOutRG, anonProof.balanceCommitNewLG, anonProof.balanceCommitNewRG, anonProof.parityG0, anonProof.parityG1))).mod();
        anonAuxiliaries.f = new uint256[2][](proof.size);
        anonAuxiliaries.f[0][0] = anonAuxiliaries.x;
        anonAuxiliaries.f[0][1] = anonAuxiliaries.x;
        for (uint i = 1; i < proof.size; i++) {
            anonAuxiliaries.f[i][0] = anonProof.f[i - 1][0];
            anonAuxiliaries.f[i][1] = anonProof.f[i - 1][1];
            anonAuxiliaries.f[0][0] = anonAuxiliaries.f[0][0].sub(anonAuxiliaries.f[i][0]);
            anonAuxiliaries.f[0][1] = anonAuxiliaries.f[0][1].sub(anonAuxiliaries.f[i][1]);
        }
        G1Point memory temp;
        for (uint256 i = 0; i < proof.size; i++) { // comparison of different types?
            temp = add(temp, mul(gs[i], anonAuxiliaries.f[i][0]));
            temp = add(temp, mul(hs[i], anonAuxiliaries.f[i][1])); // commutative
        }
        require(eq(add(mul(anonProof.B, anonAuxiliaries.x), anonProof.A), add(temp, mul(h, anonProof.zA))), "Recovery failure for B^x * A.");
        // warning: all hell will break loose if you use an anonset of size > 64
        for (uint i = 0; i < proof.size; i++) {
            anonAuxiliaries.f[i][0] = anonAuxiliaries.f[i][0].mul(anonAuxiliaries.x.sub(anonAuxiliaries.f[i][0]));
            anonAuxiliaries.f[i][1] = anonAuxiliaries.f[i][1].mul(anonAuxiliaries.x.sub(anonAuxiliaries.f[i][1]));
        }
        temp = G1Point(0, 0);
        for (uint256 i = 0; i < proof.size; i++) { // comparison of different types?
            temp = add(temp, mul(gs[i], anonAuxiliaries.f[i][0]));
            temp = add(temp, mul(hs[i], anonAuxiliaries.f[i][1])); // commutative
        }
        require(eq(add(mul(anonProof.C, anonAuxiliaries.x), anonProof.D), add(temp, mul(h, anonProof.zC))), "Recovery failure for C^x * D.");

        anonAuxiliaries.f[0][0] = anonAuxiliaries.x;
        anonAuxiliaries.f[0][1] = anonAuxiliaries.x;
        for (uint i = 1; i < proof.size; i++) { // need to recompute these. contract too large if use another variable
            anonAuxiliaries.f[i][0] = anonProof.f[i - 1][0];
            anonAuxiliaries.f[i][1] = anonProof.f[i - 1][1];
            anonAuxiliaries.f[0][0] = anonAuxiliaries.f[0][0].sub(anonAuxiliaries.f[i][0]);
            anonAuxiliaries.f[0][1] = anonAuxiliaries.f[0][1].sub(anonAuxiliaries.f[i][1]);
        }

        anonAuxiliaries.xInv = anonAuxiliaries.x.inv();
        anonAuxiliaries.inOutR2 = add(statement.R, mul(anonProof.inOutRG, anonAuxiliaries.xInv.neg()));
        anonAuxiliaries.cycler = new uint256[2][](proof.size);
        anonAuxiliaries.L2 = new G1Point[2][](proof.size / 2);
        anonAuxiliaries.y2 = new G1Point[2][](proof.size / 2);
        for (uint256 i = 0; i < proof.size / 2; i++) {
            for (uint256 j = 0; j < proof.size; j++) {
                anonAuxiliaries.cycler[j][0] = anonAuxiliaries.cycler[j][0].add(anonAuxiliaries.f[(j + i * 2) % proof.size][0]);
                anonAuxiliaries.cycler[j][1] = anonAuxiliaries.cycler[j][1].add(anonAuxiliaries.f[(j + i * 2) % proof.size][1]);
                anonAuxiliaries.L2[i][0] = add(anonAuxiliaries.L2[i][0], mul(statement.L[j], anonAuxiliaries.f[(j + i * 2) % proof.size][0]));
                anonAuxiliaries.L2[i][1] = add(anonAuxiliaries.L2[i][1], mul(statement.L[j], anonAuxiliaries.f[(j + i * 2) % proof.size][1]));
                anonAuxiliaries.y2[i][0] = add(anonAuxiliaries.y2[i][0], mul(statement.y[j], anonAuxiliaries.f[(j + i * 2) % proof.size][0]));
                anonAuxiliaries.y2[i][1] = add(anonAuxiliaries.y2[i][1], mul(statement.y[j], anonAuxiliaries.f[(j + i * 2) % proof.size][1]));
            }
            anonAuxiliaries.L2[i][0] = mul(add(anonAuxiliaries.L2[i][0], neg(anonProof.LG[i][0])), anonAuxiliaries.xInv);
            anonAuxiliaries.L2[i][1] = mul(add(anonAuxiliaries.L2[i][1], neg(anonProof.LG[i][1])), anonAuxiliaries.xInv);
            anonAuxiliaries.y2[i][0] = mul(add(anonAuxiliaries.y2[i][0], neg(anonProof.yG[i][0])), anonAuxiliaries.xInv);
            anonAuxiliaries.y2[i][1] = mul(add(anonAuxiliaries.y2[i][1], neg(anonProof.yG[i][1])), anonAuxiliaries.xInv);
        }
        for (uint256 i = 0; i < proof.size; i++) {
            anonAuxiliaries.balanceCommitNewL2 = add(anonAuxiliaries.balanceCommitNewL2, mul(statement.CL[i], anonAuxiliaries.f[i][0]));
            anonAuxiliaries.balanceCommitNewR2 = add(anonAuxiliaries.balanceCommitNewR2, mul(statement.CR[i], anonAuxiliaries.f[i][0]));
            anonAuxiliaries.parity = add(anonAuxiliaries.parity, mul(statement.y[i], anonAuxiliaries.cycler[i][0].mul(anonAuxiliaries.cycler[i][1])));
        }
        anonAuxiliaries.balanceCommitNewL2 = mul(add(anonAuxiliaries.balanceCommitNewL2, neg(anonProof.balanceCommitNewLG)), anonAuxiliaries.xInv);
        anonAuxiliaries.balanceCommitNewR2 = mul(add(anonAuxiliaries.balanceCommitNewR2, neg(anonProof.balanceCommitNewRG)), anonAuxiliaries.xInv);

        require(eq(anonAuxiliaries.parity, add(mul(anonProof.parityG1, anonAuxiliaries.x), anonProof.parityG0)), "Index opposite parity check fail.");

        anonAuxiliaries.gPrime = mul(add(mul(g, anonAuxiliaries.x), neg(anonProof.inOutRG)), anonAuxiliaries.xInv);

        SigmaProof memory sigmaProof = proof.sigmaProof;
        SigmaAuxiliaries memory sigmaAuxiliaries;
        sigmaAuxiliaries.minusC = sigmaProof.c.neg();
        sigmaAuxiliaries.AL = new G1Point[2][](proof.size / 2 - 1);
        for (uint256 i = 1; i < proof.size / 2; i++) {
            sigmaAuxiliaries.AL[i - 1][0] = add(mul(anonAuxiliaries.y2[i][0], sigmaProof.sR), mul(anonAuxiliaries.L2[i][0], sigmaAuxiliaries.minusC));
            sigmaAuxiliaries.AL[i - 1][1] = add(mul(anonAuxiliaries.y2[i][1], sigmaProof.sR), mul(anonAuxiliaries.L2[i][1], sigmaAuxiliaries.minusC));
        }
        sigmaAuxiliaries.AD = add(mul(anonAuxiliaries.gPrime, sigmaProof.sR), mul(anonAuxiliaries.inOutR2, sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.Ay = add(mul(anonAuxiliaries.gPrime, sigmaProof.sX), mul(anonAuxiliaries.y2[0][0], sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.gEpoch = mapInto("Zether", statement.epoch);
        sigmaAuxiliaries.Au = add(mul(sigmaAuxiliaries.gEpoch, sigmaProof.sX), mul(statement.u, sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.ADiff = add(mul(add(anonAuxiliaries.y2[0][0], anonAuxiliaries.y2[0][1]), sigmaProof.sR), mul(add(anonAuxiliaries.L2[0][0], anonAuxiliaries.L2[0][1]), sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.cCommit = add(add(add(mul(anonAuxiliaries.inOutR2, sigmaProof.sX.mul(zetherAuxiliaries.zSquared)), mul(anonAuxiliaries.balanceCommitNewR2, sigmaProof.sX.mul(zetherAuxiliaries.zCubed).neg())), mul(anonAuxiliaries.balanceCommitNewL2, sigmaProof.c.mul(zetherAuxiliaries.zCubed))), mul(anonAuxiliaries.L2[0][0], sigmaProof.c.mul(zetherAuxiliaries.zSquared).neg()));
        sigmaAuxiliaries.At = add(add(mul(g, zetherAuxiliaries.t.mul(sigmaProof.c)), mul(h, proof.tauX.mul(sigmaProof.c))), neg(add(sigmaAuxiliaries.cCommit, mul(zetherAuxiliaries.tEval, sigmaProof.c))));

        uint256 challenge = uint256(keccak256(abi.encode(anonAuxiliaries.x, sigmaAuxiliaries.AL, sigmaAuxiliaries.Ay, sigmaAuxiliaries.AD, sigmaAuxiliaries.Au, sigmaAuxiliaries.ADiff, sigmaAuxiliaries.At))).mod();
        require(challenge == proof.sigmaProof.c, "Sigma protocol challenge equality failure.");

        IPAuxiliaries memory ipAuxiliaries;
        ipAuxiliaries.uChallenge = uint256(keccak256(abi.encode(sigmaProof.c, proof.t, proof.tauX, proof.mu))).mod(); // uChallenge
        ipAuxiliaries.u = mul(g, ipAuxiliaries.uChallenge);
        ipAuxiliaries.hPrimes = hadamard_inv(hs, zetherAuxiliaries.ys);
        ipAuxiliaries.hExp = addVectors(times(zetherAuxiliaries.ys, zetherAuxiliaries.z), zetherAuxiliaries.twoTimesZSquared);

        ipAuxiliaries.P = add(add(proof.A, mul(proof.S, zetherAuxiliaries.x)), mul(sumPoints(gs), zetherAuxiliaries.z.neg()));
        ipAuxiliaries.P = add(neg(mul(h, proof.mu)), add(ipAuxiliaries.P, commit(ipAuxiliaries.hPrimes, ipAuxiliaries.hExp)));
        ipAuxiliaries.P = add(ipAuxiliaries.P, mul(ipAuxiliaries.u, proof.t));

        // begin inner product verification
        InnerProductProof memory ipProof = proof.ipProof;
        for (uint256 i = 0; i < n; i++) {
            ipAuxiliaries.uChallenge = uint256(keccak256(abi.encode(ipAuxiliaries.uChallenge, ipProof.ls[i], ipProof.rs[i]))).mod();
            ipAuxiliaries.challenges[i] = ipAuxiliaries.uChallenge; // overwrites value
            uint256 xInv = ipAuxiliaries.uChallenge.inv();
            ipAuxiliaries.P = add(mul(ipProof.ls[i], ipAuxiliaries.uChallenge.exp(2)), add(mul(ipProof.rs[i], xInv.exp(2)), ipAuxiliaries.P));
        }

        ipAuxiliaries.otherExponents[0] = 1;
        for (uint256 i = 0; i < n; i++) {
            ipAuxiliaries.otherExponents[0] = ipAuxiliaries.otherExponents[0].mul(ipAuxiliaries.challenges[i]);
        }
        bool[m] memory bitSet;
        ipAuxiliaries.otherExponents[0] = ipAuxiliaries.otherExponents[0].inv();
        for (uint256 i = 0; i < m/2; ++i) {
            for (uint256 j = 0; (1 << j) + i < m; ++j) {
                uint256 i1 = i + (1 << j);
                if (!bitSet[i1]) {
                    uint256 temp = ipAuxiliaries.challenges[n-1-j].mul(ipAuxiliaries.challenges[n-1-j]);
                    ipAuxiliaries.otherExponents[i1] = ipAuxiliaries.otherExponents[i].mul(temp);
                    bitSet[i1] = true;
                }
            }
        }

        G1Point memory gTemp;
        G1Point memory hTemp;
        for (uint256 i = 0; i < m; i++) {
            gTemp = add(gTemp, mul(gs[i], ipAuxiliaries.otherExponents[i]));
            hTemp = add(hTemp, mul(ipAuxiliaries.hPrimes[i], ipAuxiliaries.otherExponents[m - 1 - i]));
        }
        G1Point memory cProof = add(add(mul(gTemp, ipProof.a), mul(hTemp, ipProof.b)), mul(ipAuxiliaries.u, ipProof.a.mul(ipProof.b)));
        require(eq(ipAuxiliaries.P, cProof), "Inner product equality check failure.");

        return true;
    }

    function unserialize(bytes memory arr) internal pure returns (ZetherProof memory) {
        ZetherProof memory proof;
        proof.A = G1Point(slice(arr, 0), slice(arr, 32));
        proof.S = G1Point(slice(arr, 64), slice(arr, 96));
        proof.commits = [G1Point(slice(arr, 128), slice(arr, 160)), G1Point(slice(arr, 192), slice(arr, 224))];
        proof.t = slice(arr, 256);
        proof.tauX = slice(arr, 288);
        proof.mu = slice(arr, 320);

        SigmaProof memory sigmaProof;
        sigmaProof.c = slice(arr, 352);
        sigmaProof.sX = slice(arr, 384);
        sigmaProof.sR = slice(arr, 416);
        proof.sigmaProof = sigmaProof;

        InnerProductProof memory ipProof;
        for (uint256 i = 0; i < n; i++) {
            ipProof.ls[i] = G1Point(slice(arr, 448 + i * 64), slice(arr, 480 + i * 64));
            ipProof.rs[i] = G1Point(slice(arr, 448 + (n + i) * 64), slice(arr, 480 + (n + i) * 64));
        }
        ipProof.a = slice(arr, 448 + n * 128);
        ipProof.b = slice(arr, 480 + n * 128);
        proof.ipProof = ipProof;

        AnonProof memory anonProof;
        uint256 size = (arr.length - 1280 - 576) / 192;  // warning: this and the below assume that n = 6!!!
        anonProof.A = G1Point(slice(arr, 1280), slice(arr, 1312));
        anonProof.B = G1Point(slice(arr, 1344), slice(arr, 1376));
        anonProof.C = G1Point(slice(arr, 1408), slice(arr, 1440));
        anonProof.D = G1Point(slice(arr, 1472), slice(arr, 1504));
        anonProof.inOutRG = G1Point(slice(arr, 1536), slice(arr, 1568));
        anonProof.balanceCommitNewLG = G1Point(slice(arr, 1600), slice(arr, 1632));
        anonProof.balanceCommitNewRG = G1Point(slice(arr, 1664), slice(arr, 1696));
        anonProof.parityG0 = G1Point(slice(arr, 1728), slice(arr, 1760));
        anonProof.parityG1 = G1Point(slice(arr, 1792), slice(arr, 1824));

        anonProof.f = new uint256[2][](size - 1);
        for (uint256 i = 0; i < size - 1; i++) {
            anonProof.f[i][0] = slice(arr, 1856 + 32 * i);
            anonProof.f[i][1] = slice(arr, 1856 + (size - 1 + i) * 32);
        }

        anonProof.LG = new G1Point[2][](size / 2);
        anonProof.yG = new G1Point[2][](size / 2);
        for (uint256 i = 0; i < size / 2; i++) {
            anonProof.LG[i][0] = G1Point(slice(arr, 1792 + (size + i) * 64), slice(arr, 1824 + (size + i) * 64));
            anonProof.LG[i][1] = G1Point(slice(arr, 1792 + size * 96 + i * 64), slice(arr, 1824 + size * 96 + i * 64));
            anonProof.yG[i][0] = G1Point(slice(arr, 1792 + size * 128 + i * 64), slice(arr, 1824 + size * 128 + i * 64));
            anonProof.yG[i][1] = G1Point(slice(arr, 1792 + size * 160 + i * 64), slice(arr, 1824 + size * 160 + i * 64));
            // these are tricky, and can maybe be optimized further?
        }
        proof.size = size;

        anonProof.zA = slice(arr, 1792 + size * 192);
        anonProof.zC = slice(arr, 1824 + size * 192);

        proof.anonProof = anonProof;
        return proof;
    }

    function addVectors(uint256[m] memory a, uint256[m] memory b) internal pure returns (uint256[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
            result[i] = a[i].add(b[i]);
        }
    }

    function hadamard_inv(G1Point[m] memory ps, uint256[m] memory ss) internal view returns (G1Point[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
            result[i] = mul(ps[i], ss[i].inv());
        }
    }

    function sumScalars(uint256[m] memory ys) internal pure returns (uint256 result) {
        for (uint256 i = 0; i < m; i++) {
            result = result.add(ys[i]);
        }
    }

    function sumPoints(G1Point[m] memory ps) internal view returns (G1Point memory sum) {
        for (uint256 i = 0; i < m; i++) {
            sum = add(sum, ps[i]);
        }
    }

    function commit(G1Point[m] memory ps, uint256[m] memory ss) internal view returns (G1Point memory result) {
        for (uint256 i = 0; i < m; i++) { // killed a silly initialization with the 0th indexes. [0x00, 0x00] will be treated as the zero point anyway
            result = add(result, mul(ps[i], ss[i]));
        }
    }

    function powers(uint256 base) internal pure returns (uint256[m] memory powers) {
        powers[0] = 1;
        powers[1] = base;
        for (uint256 i = 2; i < m; i++) {
            powers[i] = powers[i-1].mul(base);
        }
    }

    function times(uint256[m] memory v, uint256 x) internal pure returns (uint256[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
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
    struct G1Point {
        uint256 x;
        uint256 y;
    }

    function add(G1Point memory p1, G1Point memory p2) public view returns (G1Point memory r) {
        assembly {
            let m := mload(0x40)
            mstore(m, mload(p1))
            mstore(add(m, 0x20), mload(add(p1, 0x20)))
            mstore(add(m, 0x40), mload(p2))
            mstore(add(m, 0x60), mload(add(p2, 0x20)))
            if iszero(staticcall(gas, 0x06, m, 0x80, r, 0x40)) {
                revert(0, 0)
            }
        }
    }

    function mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {
        assembly {
            let m := mload(0x40)
            mstore(m, mload(p))
            mstore(add(m, 0x20), mload(add(p, 0x20)))
            mstore(add(m, 0x40), s)
            if iszero(staticcall(gas, 0x07, m, 0x60, r, 0x40)) {
                revert(0, 0)
            }
        }
    }

    function neg(G1Point memory p) internal view returns (G1Point memory) {
        return G1Point(p.x, ORDER - (p.y % ORDER)); // p.y should already be reduced mod P?
    }

    function eq(G1Point memory p1, G1Point memory p2) internal pure returns (bool) {
        return p1.x == p2.x && p1.y == p2.y;
    }

    function fieldexp(uint256 base, uint256 exponent) internal view returns (uint256 output) { // warning: mod p, not q
        uint256 ORDER = ORDER;
        assembly {
            let m := mload(0x40)
            mstore(m, 0x20)
            mstore(add(m, 0x20), 0x20)
            mstore(add(m, 0x40), 0x20)
            mstore(add(m, 0x60), base)
            mstore(add(m, 0x80), exponent)
            mstore(add(m, 0xa0), ORDER)
            if iszero(staticcall(gas, 0x05, m, 0xc0, m, 0x20)) { // staticcall or call?
                revert(0, 0)
            }
            output := mload(m)
        }
    }

    function mapInto(uint256 seed) internal view returns (G1Point memory) { // warning: function totally untested!
        uint256 y;
        while (true) {
            uint256 ySquared = fieldexp(seed, 3) + 3; // addmod instead of add: waste of gas, plus function overhead cost
            y = fieldexp(ySquared, (ORDER + 1) / 4);
            if (fieldexp(y, 2) == ySquared) {
                break;
            }
            seed += 1;
        }
        return G1Point(seed, y);
    }

    function mapInto(string memory input) internal view returns (G1Point memory) { // warning: function totally untested!
        return mapInto(uint256(keccak256(abi.encodePacked(input))) % ORDER);
    }

    function mapInto(string memory input, uint256 i) internal view returns (G1Point memory) { // warning: function totally untested!
        return mapInto(uint256(keccak256(abi.encodePacked(input, i))) % ORDER);
        // ^^^ important: i haven't tested this, i.e. whether it agrees with ProofUtils.paddedHash(input, i) (cf. also the go version)
    }
}
