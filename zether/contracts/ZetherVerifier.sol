pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "./alt_bn128.sol";

contract ZetherVerifier {
    using alt_bn128 for uint256;
    using alt_bn128 for alt_bn128.G1Point;

    uint256 constant m = 64;
    uint256 constant n = 6;

    alt_bn128.G1Point[m] gs;
    alt_bn128.G1Point[m] hs;
    alt_bn128.G1Point g;
    alt_bn128.G1Point h;

    uint256[m] twos = powers(2);

    struct ZetherStatement {
        alt_bn128.G1Point[] balanceCommitNewL;
        alt_bn128.G1Point[] balanceCommitNewR;
        alt_bn128.G1Point[] L;
        alt_bn128.G1Point R;
        alt_bn128.G1Point[] y;
        uint256 epoch; // or uint8?
        alt_bn128.G1Point u;
    }

    struct ZetherProof {
        uint256 size; // not strictly necessary, but...?
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
        alt_bn128.G1Point[2][] LG; // flipping the indexing order on this, 'cause...
        alt_bn128.G1Point inOutRG;
        alt_bn128.G1Point balanceCommitNewLG;
        alt_bn128.G1Point balanceCommitNewRG;
        alt_bn128.G1Point[2][] yG; // assuming this one has the same size..., N / 2 by 2,
        alt_bn128.G1Point parityG0;
        alt_bn128.G1Point parityG1;
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
        alt_bn128.G1Point[n] ls;
        alt_bn128.G1Point[n] rs;
        uint256 a;
        uint256 b;
    }

    constructor() public {
        g = alt_bn128.mapInto("G");
        h = alt_bn128.mapInto("V");
        for (uint256 i = 0; i < m; i++) {
            gs[i] = alt_bn128.mapInto("G", i);
            hs[i] = alt_bn128.mapInto("H", i);
        }
    }

    function verify(bytes32[2][] memory CL, bytes32[2][] memory CR, bytes32[2][] memory L, bytes32[2] memory R, bytes32[2][] memory y, uint256 epoch, bytes32[2] memory u, bytes memory proof) view public returns (bool) {
        ZetherStatement memory statement;
        uint256 size = y.length;
        statement.balanceCommitNewL = new alt_bn128.G1Point[](size);
        statement.balanceCommitNewR = new alt_bn128.G1Point[](size);
        statement.L = new alt_bn128.G1Point[](size);
        statement.y = new alt_bn128.G1Point[](size);
        for (uint256 i = 0; i < size; i++) {
            statement.balanceCommitNewL[i] = alt_bn128.G1Point(uint256(CL[i][0]), uint256(CL[i][1]));
            statement.balanceCommitNewR[i] = alt_bn128.G1Point(uint256(CR[i][0]), uint256(CR[i][1]));
            statement.L[i] = alt_bn128.G1Point(uint256(L[i][0]), uint256(L[i][1]));
            statement.y[i] = alt_bn128.G1Point(uint256(y[i][0]), uint256(y[i][1]));
        }
        statement.R = alt_bn128.G1Point(uint256(R[0]), uint256(R[1]));
        statement.epoch = epoch;
        statement.u = alt_bn128.G1Point(uint256(u[0]), uint256(u[1]));
        ZetherProof memory zetherProof = unserialize(proof);
        return verifyTransfer(statement, zetherProof);
        return true;
    }

    struct ZetherAuxiliaries {
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
        alt_bn128.G1Point[2][] AL;
        alt_bn128.G1Point Ay;
        alt_bn128.G1Point AD;
        alt_bn128.G1Point gEpoch;
        alt_bn128.G1Point Au;
        alt_bn128.G1Point ADiff;
        alt_bn128.G1Point cCommit;
        alt_bn128.G1Point At;
    }

    struct AnonAuxiliaries {
        uint256 x;
        uint256[2][] f;
        uint256 xInv;
        alt_bn128.G1Point inOutR2;
        alt_bn128.G1Point balanceCommitNewL2;
        alt_bn128.G1Point balanceCommitNewR2;
        uint256[2][] cycler;
        alt_bn128.G1Point[2][] L2;
        alt_bn128.G1Point[2][] y2;
        alt_bn128.G1Point parity;
        alt_bn128.G1Point gPrime;
    }

    struct IPAuxiliaries {
        alt_bn128.G1Point u;
        alt_bn128.G1Point[m] hPrimes;
        uint256[m] hExp;
        alt_bn128.G1Point P;
        uint256 uChallenge;
        uint256[n] challenges;
        uint256[m] otherExponents;
    }

    function verifyTransfer(ZetherStatement memory statement, ZetherProof memory proof) view internal returns (bool) {
        require(proof.size % 2 == 0, "Anonymity set size must be even!"); // could also do this during deserialization?

        ZetherAuxiliaries memory zetherAuxiliaries;
        zetherAuxiliaries.y = uint256(keccak256(abi.encode(keccak256(abi.encode(statement.epoch, statement.R, statement.balanceCommitNewL, statement.balanceCommitNewR, statement.L, statement.y)), proof.A, proof.S))).mod();
        // warning: not correct as written. the encoding will include length headers, whereas the java version does not!
        zetherAuxiliaries.ys = powers(zetherAuxiliaries.y);
        zetherAuxiliaries.z = uint256(keccak256(abi.encode(zetherAuxiliaries.y))).mod();
        zetherAuxiliaries.zSquared = zetherAuxiliaries.z.mul(zetherAuxiliaries.z);
        zetherAuxiliaries.zCubed = zetherAuxiliaries.zSquared.mul(zetherAuxiliaries.z);
        zetherAuxiliaries.twoTimesZSquared = times(twos, zetherAuxiliaries.zSquared);
        zetherAuxiliaries.x = uint256(keccak256(abi.encode(zetherAuxiliaries.z, proof.commits[0], proof.commits[1]))).mod();

        uint256 zSum = zetherAuxiliaries.zSquared.add(zetherAuxiliaries.zCubed).mul(zetherAuxiliaries.z);
        zetherAuxiliaries.k = sumScalars(zetherAuxiliaries.ys).mul(zetherAuxiliaries.z.sub(zetherAuxiliaries.zSquared)).sub(zSum.mul(2 ** m).sub(zSum));
        zetherAuxiliaries.tEval = proof.commits[0].mul(zetherAuxiliaries.x).add(proof.commits[1].mul(zetherAuxiliaries.x.mul(zetherAuxiliaries.x))); // replace with "commit"?
        zetherAuxiliaries.t = proof.t.sub(zetherAuxiliaries.k);

        // begin anon proof.
        // length equality checks for anonProof members? or during deserialization?
        AnonProof memory anonProof = proof.anonProof;
        AnonAuxiliaries memory anonAuxiliaries;
        anonAuxiliaries.x = uint256(keccak256(abi.encode(zetherAuxiliaries.x, anonProof.LG, anonProof.yG, anonProof.A, anonProof.B, anonProof.C, anonProof.D, anonProof.inOutRG, anonProof.balanceCommitNewLG, anonProof.balanceCommitNewRG, anonProof.parityG0, anonProof.parityG1))).mod();
        // warning: will encode length headers, while java will not
        anonAuxiliaries.f = new uint256[2][](proof.size);
        anonAuxiliaries.f[0][0] = anonAuxiliaries.x;
        anonAuxiliaries.f[0][1] = anonAuxiliaries.x;
        for (uint i = 1; i < proof.size; i++) {
            anonAuxiliaries.f[i][0] = anonProof.f[i][0];
            anonAuxiliaries.f[i][1] = anonProof.f[i][1];
            anonAuxiliaries.f[0][0] = anonAuxiliaries.f[0][0].sub(anonAuxiliaries.f[i][0]);
            anonAuxiliaries.f[0][1] = anonAuxiliaries.f[0][1].sub(anonAuxiliaries.f[i][1]);
        }
        alt_bn128.G1Point memory temp = double(gs, hs, anonAuxiliaries.f);
        require(anonProof.B.mul(anonAuxiliaries.x).add(anonProof.A).eq(temp.mul(anonProof.zA)), "Recovery failure for B^x * A.");
        for (uint i = 0; i < proof.size; i++) {
            anonAuxiliaries.f[i][0] = anonAuxiliaries.x.sub(anonAuxiliaries.f[i][0]);
            anonAuxiliaries.f[i][1] = anonAuxiliaries.x.sub(anonAuxiliaries.f[i][1]);
        }
        require(anonProof.C.mul(anonAuxiliaries.x).add(anonProof.D).eq(temp.mul(anonProof.zC)), "Recovery failure for C^x * D.");
        anonAuxiliaries.xInv = anonAuxiliaries.x.inv();
        anonAuxiliaries.inOutR2 = statement.R.add(anonProof.inOutRG.mul(anonAuxiliaries.x.neg()));
        anonAuxiliaries.cycler = new uint256[2][](proof.size);
        anonAuxiliaries.L2 = new alt_bn128.G1Point[2][](proof.size);
        anonAuxiliaries.y2 = new alt_bn128.G1Point[2][](proof.size);
        for (uint256 i = 0; i < proof.size / 2; i++) {
            for (uint256 j = 0; j < proof.size; j++) {
                anonAuxiliaries.cycler[j][0] = anonAuxiliaries.cycler[j][0].add(anonAuxiliaries.f[j + i * 2][0]);
                anonAuxiliaries.cycler[j][1] = anonAuxiliaries.cycler[j][1].add(anonAuxiliaries.f[j + i * 2][1]);
                anonAuxiliaries.L2[i][0] = anonAuxiliaries.L2[i][0].add(statement.L[j].mul(anonAuxiliaries.f[j + i * 2][0]));
                anonAuxiliaries.L2[i][1] = anonAuxiliaries.L2[i][1].add(statement.L[j].mul(anonAuxiliaries.f[j + i * 2][1]));
                anonAuxiliaries.y2[i][0] = anonAuxiliaries.y2[i][0].add(statement.y[j].mul(anonAuxiliaries.f[j + i * 2][0]));
                anonAuxiliaries.y2[i][1] = anonAuxiliaries.y2[i][1].add(statement.y[j].mul(anonAuxiliaries.f[j + i * 2][1]));
            }
            anonAuxiliaries.L2[i][0] = anonAuxiliaries.L2[i][0].add(anonProof.LG[i][0]).mul(anonAuxiliaries.xInv);
            anonAuxiliaries.L2[i][1] = anonAuxiliaries.L2[i][1].add(anonProof.LG[i][1]).mul(anonAuxiliaries.xInv);
        }
        for (uint256 i = 0; i < proof.size; i++) {
            anonAuxiliaries.balanceCommitNewL2 = anonAuxiliaries.balanceCommitNewL2.add(statement.balanceCommitNewL[i].mul(anonAuxiliaries.f[i][0]));
            anonAuxiliaries.balanceCommitNewR2 = anonAuxiliaries.balanceCommitNewR2.add(statement.balanceCommitNewR[i].mul(anonAuxiliaries.f[i][0]));
            anonAuxiliaries.parity = anonAuxiliaries.parity.add(statement.y[i].mul(anonAuxiliaries.cycler[i][0].mul(anonAuxiliaries.cycler[i][1])));
        }

        require(anonAuxiliaries.parity.eq(anonProof.parityG1.mul(anonAuxiliaries.x).add(anonProof.parityG0)), "Index opposite parity check fail.");

        anonAuxiliaries.gPrime = g.mul(anonAuxiliaries.x).add(anonProof.inOutRG.neg()).mul(anonAuxiliaries.xInv);

        SigmaProof memory sigmaProof = proof.sigmaProof;
        SigmaAuxiliaries memory sigmaAuxiliaries;
        sigmaAuxiliaries.minusC = sigmaProof.c.neg();
        sigmaAuxiliaries.AL = new alt_bn128.G1Point[2][](proof.size / 2 - 1);
        for (uint256 i = 1; i < proof.size / 2; i++) {
            sigmaAuxiliaries.AL[i - 1][0] = anonAuxiliaries.y2[i][0].mul(sigmaProof.sR).add(anonAuxiliaries.L2[i][0]).mul(sigmaAuxiliaries.minusC);
            sigmaAuxiliaries.AL[i - 1][1] = anonAuxiliaries.y2[i][1].mul(sigmaProof.sR).add(anonAuxiliaries.L2[i][1]).mul(sigmaAuxiliaries.minusC);
        }
        sigmaAuxiliaries.Ay = anonAuxiliaries.gPrime.mul(sigmaProof.sX).add(anonAuxiliaries.y2[0][0].mul(sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.gEpoch = alt_bn128.mapInto("Zether", statement.epoch);
        sigmaAuxiliaries.Au = sigmaAuxiliaries.gEpoch.mul(sigmaProof.sX).add(statement.u.mul(sigmaProof.c.neg()));
        sigmaAuxiliaries.ADiff = anonAuxiliaries.y2[0][0].add(anonAuxiliaries.y2[0][1]).mul(sigmaProof.sR).add(anonAuxiliaries.L2[0][0].add(anonAuxiliaries.L2[0][1])).mul(sigmaAuxiliaries.minusC);
        sigmaAuxiliaries.cCommit = anonAuxiliaries.inOutR2.mul(sigmaProof.sX.mul(zetherAuxiliaries.zSquared)).add(anonAuxiliaries.balanceCommitNewR2.mul(sigmaProof.sX.mul(zetherAuxiliaries.zCubed)).neg()).add(anonAuxiliaries.balanceCommitNewL2.mul(sigmaProof.c.mul(zetherAuxiliaries.zCubed))).add(anonAuxiliaries.L2[0][0].mul(sigmaProof.c.mul(zetherAuxiliaries.zSquared)).neg());
        sigmaAuxiliaries.At = g.mul(zetherAuxiliaries.t.mul(sigmaProof.c)).add(h.mul(proof.tauX.mul(sigmaProof.c))).add(sigmaAuxiliaries.cCommit.add(zetherAuxiliaries.tEval.mul(sigmaProof.c)).neg());

        uint256 challenge = uint256(keccak256(abi.encode(anonAuxiliaries.x, sigmaAuxiliaries.AL, sigmaAuxiliaries.Ay, sigmaAuxiliaries.AD, sigmaAuxiliaries.Au, sigmaAuxiliaries.ADiff, sigmaAuxiliaries.At))).mod();
        // warning: abi encoding difference vs. java
        require(challenge == proof.sigmaProof.c, "Sigma protocol challenge equality failure.");

        IPAuxiliaries memory ipAuxiliaries;
        ipAuxiliaries.uChallenge = uint256(keccak256(abi.encode(sigmaProof.c, proof.t, proof.tauX, proof.mu))).mod(); // uChallenge
        ipAuxiliaries.u = g.mul(ipAuxiliaries.uChallenge);
        ipAuxiliaries.hPrimes = hadamard_inv(hs, zetherAuxiliaries.ys);
        ipAuxiliaries.hExp = addVectors(times(zetherAuxiliaries.ys, zetherAuxiliaries.z), zetherAuxiliaries.twoTimesZSquared);
        ipAuxiliaries.P = proof.A.add(proof.S.mul(zetherAuxiliaries.x)).add(sumPoints(gs).mul(zetherAuxiliaries.z.neg())).add(commit(ipAuxiliaries.hPrimes, ipAuxiliaries.hExp)).add(h.mul(proof.mu).neg()).add(ipAuxiliaries.u.mul(proof.t));

        // begin inner product verification
        InnerProductProof memory ipProof = proof.ipProof;
        for (uint256 i = 0; i < n; i++) {
            ipAuxiliaries.uChallenge = uint256(keccak256(abi.encode(ipAuxiliaries.uChallenge, ipProof.ls[i], ipProof.rs[i]))).mod();
            ipAuxiliaries.challenges[i] = ipAuxiliaries.uChallenge; // overwrites value
            uint256 xInv = ipAuxiliaries.uChallenge.inv();
            ipAuxiliaries.P = ipProof.ls[i].mul(ipAuxiliaries.uChallenge.exp(2)).add(ipProof.rs[i].mul(xInv.exp(2))).add(ipAuxiliaries.P);
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

        alt_bn128.G1Point memory gTemp = multiExpGs(ipAuxiliaries.otherExponents);
        alt_bn128.G1Point memory hTemp = multiExpHsInversed(ipAuxiliaries.otherExponents, ipAuxiliaries.hPrimes);
        alt_bn128.G1Point memory cProof = gTemp.mul(ipProof.a).add(hTemp.mul(ipProof.b)).add(ipAuxiliaries.u.mul(ipProof.a.mul(ipProof.b)));
        require(ipAuxiliaries.P.eq(cProof), "Inner product equality check failure.");
        return true;
    }

    function multiExpGs(uint256[m] memory ss) internal view returns (alt_bn128.G1Point memory result) {
        // revisit whether sloads can be saved by passing gs into memory once. same as below, and for burn.
        for (uint256 i = 0; i < m; i++) {
            result = result.add(gs[i].mul(ss[i]));
        }
    }

    function multiExpHsInversed(uint256[m] memory ss, alt_bn128.G1Point[m] memory hs) internal view returns (alt_bn128.G1Point memory result) {
        for (uint256 i = 0; i < m; i++) {
            result = result.add(hs[i].mul(ss[m-1-i]));
        }
    }

    function unserialize(bytes memory arr) internal pure returns (ZetherProof memory) {
        ZetherProof memory proof;
        proof.A = alt_bn128.G1Point(slice(arr, 0), slice(arr, 32));
        proof.S = alt_bn128.G1Point(slice(arr, 64), slice(arr, 96));
        proof.commits = [alt_bn128.G1Point(slice(arr, 128), slice(arr, 160)), alt_bn128.G1Point(slice(arr, 192), slice(arr, 224))];
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
            ipProof.ls[i] = alt_bn128.G1Point(slice(arr, 448 + i * 64), slice(arr, 480 + i * 64));
            ipProof.rs[i] = alt_bn128.G1Point(slice(arr, 448 + (n + i) * 64), slice(arr, 480 + (n + i) * 64));
        }
        ipProof.a = slice(arr, 448 + n * 128);
        ipProof.b = slice(arr, 480 + n * 128);
        proof.ipProof = ipProof;

        AnonProof memory anonProof;
        uint256 size = (arr.length - 1280 - 576) / 192;  // warning: this and the below assume that n = 6!!!
        anonProof.A = alt_bn128.G1Point(slice(arr, 1280), slice(arr, 1312));
        anonProof.B = alt_bn128.G1Point(slice(arr, 1344), slice(arr, 1376));
        anonProof.C = alt_bn128.G1Point(slice(arr, 1408), slice(arr, 1440));
        anonProof.D = alt_bn128.G1Point(slice(arr, 1472), slice(arr, 1504));
        anonProof.inOutRG = alt_bn128.G1Point(slice(arr, 1536), slice(arr, 1568));
        anonProof.balanceCommitNewLG = alt_bn128.G1Point(slice(arr, 1600), slice(arr, 1632));
        anonProof.balanceCommitNewRG = alt_bn128.G1Point(slice(arr, 1664), slice(arr, 1696));
        anonProof.parityG0 = alt_bn128.G1Point(slice(arr, 1728), slice(arr, 1760));
        anonProof.parityG1 = alt_bn128.G1Point(slice(arr, 1792), slice(arr, 1824));
        for (uint256 i = 0; i < size - 1; i++) {
            anonProof.f[i][0] = slice(arr, 1856 + 32 * i);
            anonProof.f[i][1] = slice(arr, 1856 + (size - 1 + i) * 32);
        }

        for (uint256 i = 0; i < size / 2; i++) {
            anonProof.LG[i][0] = alt_bn128.G1Point(slice(arr, 1792 + (size + i) * 64), slice(arr, 1824 + (size + i) * 64));
            anonProof.LG[i][1] = alt_bn128.G1Point(slice(arr, 1792 + size * 96 + i * 64), slice(arr, 1824 + size * 96 + i * 64));
            anonProof.yG[i][0] = alt_bn128.G1Point(slice(arr, 1792 + size * 128 + i * 64), slice(arr, 1824 + size * 128 + i * 64));
            anonProof.yG[i][1] = alt_bn128.G1Point(slice(arr, 1792 + size * 160 + i * 64), slice(arr, 1824 + size * 160 + i * 64));
            // these are tricky, and can maybe be optimized further?
        }

        proof.anonProof = anonProof;
        return proof;
    }

    function addVectors(uint256[m] memory a, uint256[m] memory b) internal pure returns (uint256[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
            result[i] = a[i].add(b[i]);
        }
    }

    function hadamard_inv(alt_bn128.G1Point[m] memory ps, uint256[m] memory ss) internal view returns (alt_bn128.G1Point[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
            result[i] = ps[i].mul(ss[i].inv());
        }
    }

    function sumScalars(uint256[m] memory ys) internal pure returns (uint256 result) {
        for (uint256 i = 0; i < m; i++) {
            result = result.add(ys[i]);
        }
    }

    function sumPoints(alt_bn128.G1Point[m] memory ps) internal view returns (alt_bn128.G1Point memory sum) {
        for (uint256 i = 0; i < m; i++) {
            sum = sum.add(ps[i]);
        }
    }

    function commit(alt_bn128.G1Point[m] memory ps, uint256[m] memory ss) internal view returns (alt_bn128.G1Point memory result) {
        for (uint256 i = 0; i < m; i++) { // killed a silly initialization with the 0th indexes. [0x00, 0x00] will be treated as the zero point anyway
            result = result.add(ps[i].mul(ss[i]));
        }
    }

    function double(alt_bn128.G1Point[m] memory gs, alt_bn128.G1Point[m] memory hs, uint256[2][] memory f) internal view returns (alt_bn128.G1Point memory result) {
        // trying to save some sloads here ^^^ do i save by loading the whole array at once?
        uint256 size = f.length;
        for (uint256 i = 0; i < size; i++) { // comparison of different types?
            result = result.add(gs[i].mul(f[i][0]));
            result = result.add(hs[i].mul(f[i][1])); // commutative
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
}
