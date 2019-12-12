pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "./Utils.sol";

contract ZetherVerifier {
    using Utils for uint256;

    uint256 constant m = 64;
    uint256 constant n = 6;
    uint256 constant FIELD_ORDER = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint256 constant UNITY = 9334303377689037989442018753807510978357674015322511348041267794643984346845; // primitive 2^28th root of unity modulo GROUP_ORDER (not field!)

    G1Point[] gs; // warning: this and the below are not statically sized anymore
    G1Point[] hs; // need to push to these if large anonsets are used.
    G1Point g;
    G1Point h;

    struct ZetherStatement {
        G1Point[] CLn;
        G1Point[] CRn;
        G1Point[] C;
        G1Point D;
        G1Point[] y;
        uint256 epoch; // or uint8?
        G1Point u;
    }

    struct ZetherProof {
        G1Point BA;
        G1Point BS;
        G1Point A;
        G1Point B;
        G1Point C;
        G1Point D;
        G1Point E;
        G1Point F;

        G1Point[] CLnG;
        G1Point[] CRnG;
        G1Point[] C_0G;
        G1Point[] DG;
        G1Point[] y_0G;
        G1Point[] gG;
        G1Point[] C_XG;
        G1Point[] y_XG;

        uint256[] f;
        uint256 z_A;
        uint256 z_C;
        uint256 z_E;

        G1Point CPrime;
        G1Point DPrime;
        G1Point CLnPrime;
        G1Point CRnPrime;

        G1Point[2] tCommits;
        uint256 tHat;
        uint256 tauX;
        uint256 mu;

        uint256 c;
        uint256 s_sk;
        uint256 s_r;
        uint256 s_vTransfer;
        uint256 s_vDiff;
        uint256 s_nuTransfer;
        uint256 s_nuDiff;

        InnerProductProof ipProof;
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
            gs.push(mapInto("G", i));
            hs.push(mapInto("H", i));
        }
    }

    function verifyTransfer(bytes32[2][] memory CLn, bytes32[2][] memory CRn, bytes32[2][] memory C, bytes32[2] memory D, bytes32[2][] memory y, uint256 epoch, bytes32[2] memory u, bytes memory proof) view public returns (bool) {
        ZetherStatement memory statement;
        uint256 size = y.length;

        statement.CLn = new G1Point[](size);
        statement.CRn = new G1Point[](size);
        statement.C = new G1Point[](size);
        statement.y = new G1Point[](size);
        for (uint256 i = 0; i < size; i++) {
            statement.CLn[i] = G1Point(uint256(CLn[i][0]), uint256(CLn[i][1]));
            statement.CRn[i] = G1Point(uint256(CRn[i][0]), uint256(CRn[i][1]));
            statement.C[i] = G1Point(uint256(C[i][0]), uint256(C[i][1]));
            statement.y[i] = G1Point(uint256(y[i][0]), uint256(y[i][1]));
        }
        statement.D = G1Point(uint256(D[0]), uint256(D[1]));
        statement.epoch = epoch;
        statement.u = G1Point(uint256(u[0]), uint256(u[1]));
        ZetherProof memory zetherProof = unserialize(proof);
        return verify(statement, zetherProof);
    }

    struct ZetherAuxiliaries {
        uint256 y;
        uint256[m] ys;
        uint256 z;
        uint256[2] zs; // [z^2, z^3]
        uint256[m] twoTimesZSquared;
        uint256 zSum;
        uint256 x;
        uint256 t;
        uint256 k;
        G1Point tEval;
    }

    struct SigmaAuxiliaries {
        uint256 c;
        G1Point A_y;
        G1Point A_D;
        G1Point gEpoch;
        G1Point A_u;
        G1Point A_B;
        G1Point A_X;
        G1Point c_commit;
        G1Point A_t;
        G1Point A_C0;
        G1Point A_CLn;
        G1Point A_CPrime;
        G1Point A_CLnPrime;
    }

    struct AnonAuxiliaries {
        uint256 m;
        uint256 N;
        uint256 d;
        uint256 w;
        uint256 dPow;
        uint256 wPow;
        uint256[2][] f; // could just allocate extra space in the proof?
        uint256[2][] r; // each poly is an array of length N. evaluations of prods
        G1Point temp;
        G1Point CLnR;
        G1Point CRnR;
        G1Point[2][] CR;
        G1Point[2][] yR;
        G1Point C_XR;
        G1Point y_XR;
        G1Point gR;
        G1Point DR;
    }

    struct IPAuxiliaries {
        G1Point u_x;
        G1Point[m] hPrimes;
        uint256[m] hExp;
        G1Point P;
        uint256 o;
        uint256[n] challenges;
        uint256[m] otherExponents;
    }

    function verify(ZetherStatement memory statement, ZetherProof memory proof) view internal returns (bool) {
        uint256 statementHash = uint256(keccak256(abi.encode(statement.CLn, statement.CRn, statement.C, statement.D, statement.y, statement.epoch))).mod();

        AnonAuxiliaries memory anonAuxiliaries;
        anonAuxiliaries.d = uint256(keccak256(abi.encode(statementHash, proof.BA, proof.BS, proof.A, proof.B, proof.C, proof.D, proof.E, proof.F))).mod();
        anonAuxiliaries.w = uint256(keccak256(abi.encode(anonAuxiliaries.d, proof.CLnG, proof.CRnG, proof.C_0G, proof.DG, proof.y_0G, proof.gG, proof.C_XG, proof.y_XG))).mod();
        anonAuxiliaries.m = proof.f.length / 2;
        anonAuxiliaries.N = 2 ** anonAuxiliaries.m;
        anonAuxiliaries.f = new uint256[2][](2 * anonAuxiliaries.m);
        for (uint256 k = 0; k < 2 * anonAuxiliaries.m; k++) {
            anonAuxiliaries.f[k][1] = proof.f[k];
            anonAuxiliaries.f[k][0] = anonAuxiliaries.w.sub(proof.f[k]);
        }

        for (uint256 k = 0; k < 2 * anonAuxiliaries.m; k++) {
            anonAuxiliaries.temp = add(anonAuxiliaries.temp, mul(gs[k], anonAuxiliaries.f[k][1]));
        }
        require(eq(add(mul(proof.B, anonAuxiliaries.w), proof.A), add(anonAuxiliaries.temp, mul(h, proof.z_A))), "Recovery failure for B^w * A.");

        anonAuxiliaries.temp = G1Point(0, 0);
        for (uint256 k = 0; k < 2 * anonAuxiliaries.m; k++) { // danger... gs and hs need to be big enough.
            anonAuxiliaries.temp = add(anonAuxiliaries.temp, mul(gs[k], anonAuxiliaries.f[k][1].mul(anonAuxiliaries.w.sub(anonAuxiliaries.f[k][1]))));
        }
        require(eq(add(mul(proof.C, anonAuxiliaries.w), proof.D), add(anonAuxiliaries.temp, mul(h, proof.z_C))), "Recovery failure for C^w * D.");

        anonAuxiliaries.temp = add(mul(gs[0], anonAuxiliaries.f[0][1].mul(anonAuxiliaries.f[anonAuxiliaries.m][1])), mul(gs[1], anonAuxiliaries.f[0][0].mul(anonAuxiliaries.f[anonAuxiliaries.m][0])));
        require(eq(add(mul(proof.F, anonAuxiliaries.w), proof.E), add(anonAuxiliaries.temp, mul(h, proof.z_E))), "Recovery failure for F^w * E.");

        anonAuxiliaries.r = assemblePolynomials(anonAuxiliaries.f);

        anonAuxiliaries.CR = assembleConvolutions(anonAuxiliaries.r, statement.C);
        anonAuxiliaries.yR = assembleConvolutions(anonAuxiliaries.r, statement.y);
        for (uint256 i = 0; i < anonAuxiliaries.N; i++) {
            anonAuxiliaries.CLnR = add(anonAuxiliaries.CLnR, mul(statement.CLn[i], anonAuxiliaries.r[i][0]));
            anonAuxiliaries.CRnR = add(anonAuxiliaries.CRnR, mul(statement.CRn[i], anonAuxiliaries.r[i][0]));
        }
        anonAuxiliaries.dPow = 1;
        for (uint256 i = 0; i < anonAuxiliaries.N; i++) {
            anonAuxiliaries.C_XR = add(anonAuxiliaries.C_XR, mul(anonAuxiliaries.CR[i / 2][i % 2], anonAuxiliaries.dPow));
            anonAuxiliaries.y_XR = add(anonAuxiliaries.y_XR, mul(anonAuxiliaries.yR[i / 2][i % 2], anonAuxiliaries.dPow));
            if (i > 0) {
                anonAuxiliaries.dPow = anonAuxiliaries.dPow.mul(anonAuxiliaries.d);
            }
        }
        anonAuxiliaries.wPow = 1;
        for (uint256 k = 0; k < anonAuxiliaries.m; k++) {
            anonAuxiliaries.CLnR = add(anonAuxiliaries.CLnR, mul(proof.CLnG[k], anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.CRnR = add(anonAuxiliaries.CRnR, mul(proof.CRnG[k], anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.CR[0][0] = add(anonAuxiliaries.CR[0][0], mul(proof.C_0G[k], anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.DR = add(anonAuxiliaries.DR, mul(proof.DG[k], anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.yR[0][0] = add(anonAuxiliaries.yR[0][0], mul(proof.y_0G[k], anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.gR = add(anonAuxiliaries.gR, mul(proof.gG[k], anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.C_XR = add(anonAuxiliaries.C_XR, mul(proof.C_XG[k], anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.y_XR = add(anonAuxiliaries.y_XR, mul(proof.y_XG[k], anonAuxiliaries.wPow.neg()));

            anonAuxiliaries.wPow = anonAuxiliaries.wPow.mul(anonAuxiliaries.w);
        }
        anonAuxiliaries.DR = add(anonAuxiliaries.DR, mul(statement.D, anonAuxiliaries.wPow));
        anonAuxiliaries.gR = add(anonAuxiliaries.gR, mul(g, anonAuxiliaries.wPow));

        ZetherAuxiliaries memory zetherAuxiliaries;
        zetherAuxiliaries.y = uint256(keccak256(abi.encode(anonAuxiliaries.w, proof.CPrime, proof.DPrime, proof.CLnPrime, proof.CRnPrime))).mod();
        zetherAuxiliaries.ys = powers(zetherAuxiliaries.y);
        zetherAuxiliaries.z = uint256(keccak256(abi.encode(zetherAuxiliaries.y))).mod();
        zetherAuxiliaries.zs = [zetherAuxiliaries.z.exp(2), zetherAuxiliaries.z.exp(3)];        
        zetherAuxiliaries.zSum = zetherAuxiliaries.zs[0].add(zetherAuxiliaries.zs[1]).mul(zetherAuxiliaries.z);
        zetherAuxiliaries.k = sumScalars(zetherAuxiliaries.ys).mul(zetherAuxiliaries.z.sub(zetherAuxiliaries.zs[0])).sub(zetherAuxiliaries.zSum.mul(2 ** (m / 2)).sub(zetherAuxiliaries.zSum));
        zetherAuxiliaries.t = proof.tHat.sub(zetherAuxiliaries.k);
        for (uint256 i = 0; i < m / 2; i++) {
            zetherAuxiliaries.twoTimesZSquared[i] = zetherAuxiliaries.zs[0].mul(2 ** i);
            zetherAuxiliaries.twoTimesZSquared[i + m / 2] = zetherAuxiliaries.zs[1].mul(2 ** i);
        }

        zetherAuxiliaries.x = uint256(keccak256(abi.encode(zetherAuxiliaries.z, proof.tCommits))).mod();
        zetherAuxiliaries.tEval = add(mul(proof.tCommits[0], zetherAuxiliaries.x), mul(proof.tCommits[1], zetherAuxiliaries.x.mul(zetherAuxiliaries.x))); // replace with "commit"?

        SigmaAuxiliaries memory sigmaAuxiliaries;
        sigmaAuxiliaries.A_y = add(mul(anonAuxiliaries.gR, proof.s_sk), mul(anonAuxiliaries.yR[0][0], proof.c.neg()));
        sigmaAuxiliaries.A_D = add(mul(g, proof.s_r), mul(statement.D, proof.c.neg())); // add(mul(anonAuxiliaries.gR, proof.s_r), mul(anonAuxiliaries.DR, proof.c.neg()));
        sigmaAuxiliaries.gEpoch = mapInto("Zether", statement.epoch);
        sigmaAuxiliaries.A_u = add(mul(sigmaAuxiliaries.gEpoch, proof.s_sk), mul(statement.u, proof.c.neg()));
        sigmaAuxiliaries.A_X = add(mul(anonAuxiliaries.y_XR, proof.s_r), mul(anonAuxiliaries.C_XR, proof.c.neg()));
        sigmaAuxiliaries.c_commit = add(mul(add(mul(add(anonAuxiliaries.DR, proof.DPrime), proof.s_sk), mul(add(anonAuxiliaries.CR[0][0], proof.CPrime), proof.c.neg())), zetherAuxiliaries.zs[0]), mul(add(mul(add(anonAuxiliaries.CRnR, proof.CRnPrime), proof.s_sk), mul(add(anonAuxiliaries.CLnR, proof.CLnPrime), proof.c.neg())), zetherAuxiliaries.zs[1]));
        sigmaAuxiliaries.A_t = add(mul(add(add(mul(g, zetherAuxiliaries.t), mul(h, proof.tauX)), neg(zetherAuxiliaries.tEval)), proof.c.mul(anonAuxiliaries.wPow)), sigmaAuxiliaries.c_commit);
        sigmaAuxiliaries.A_C0 = add(mul(g, proof.s_vTransfer), add(mul(anonAuxiliaries.DR, proof.s_sk), mul(anonAuxiliaries.CR[0][0], proof.c.neg())));
        sigmaAuxiliaries.A_CLn = add(mul(g, proof.s_vDiff), add(mul(anonAuxiliaries.CRnR, proof.s_sk), mul(anonAuxiliaries.CLnR, proof.c.neg())));
        sigmaAuxiliaries.A_CPrime = add(mul(h, proof.s_nuTransfer), add(mul(proof.DPrime, proof.s_sk), mul(proof.CPrime, proof.c.neg())));
        sigmaAuxiliaries.A_CLnPrime = add(mul(h, proof.s_nuDiff), add(mul(proof.CRnPrime, proof.s_sk), mul(proof.CLnPrime, proof.c.neg())));

        sigmaAuxiliaries.c = uint256(keccak256(abi.encode(zetherAuxiliaries.x, sigmaAuxiliaries.A_y, sigmaAuxiliaries.A_D, sigmaAuxiliaries.A_u, sigmaAuxiliaries.A_X, sigmaAuxiliaries.A_t, sigmaAuxiliaries.A_C0, sigmaAuxiliaries.A_CLn, sigmaAuxiliaries.A_CPrime, sigmaAuxiliaries.A_CLnPrime))).mod();
        require(sigmaAuxiliaries.c == proof.c, "Sigma protocol challenge equality failure.");

        IPAuxiliaries memory ipAuxiliaries;
        ipAuxiliaries.o = uint256(keccak256(abi.encode(sigmaAuxiliaries.c))).mod();
        ipAuxiliaries.u_x = mul(g, ipAuxiliaries.o);
        ipAuxiliaries.hPrimes = hadamardInv(hs, zetherAuxiliaries.ys);
        ipAuxiliaries.hExp = addVectors(times(zetherAuxiliaries.ys, zetherAuxiliaries.z), zetherAuxiliaries.twoTimesZSquared);
        ipAuxiliaries.P = add(add(add(proof.BA, mul(proof.BS, zetherAuxiliaries.x)), mul(sumPoints(gs), zetherAuxiliaries.z.neg())), commit(ipAuxiliaries.hPrimes, ipAuxiliaries.hExp));
        ipAuxiliaries.P = add(ipAuxiliaries.P, mul(h, proof.mu.neg()));
        ipAuxiliaries.P = add(ipAuxiliaries.P, mul(ipAuxiliaries.u_x, proof.tHat));

        // begin inner product verification
        InnerProductProof memory ipProof = proof.ipProof;
        for (uint256 i = 0; i < n; i++) {
            ipAuxiliaries.o = uint256(keccak256(abi.encode(ipAuxiliaries.o, ipProof.ls[i], ipProof.rs[i]))).mod();
            ipAuxiliaries.challenges[i] = ipAuxiliaries.o; // overwrites value
            uint256 xInv = ipAuxiliaries.o.inv();
            ipAuxiliaries.P = add(ipAuxiliaries.P, add(mul(ipProof.ls[i], ipAuxiliaries.o.exp(2)), mul(ipProof.rs[i], xInv.exp(2))));
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
                    uint256 temp = ipAuxiliaries.challenges[n - 1 - j].mul(ipAuxiliaries.challenges[n - 1 - j]);
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
        G1Point memory cProof = add(add(mul(gTemp, ipProof.a), mul(hTemp, ipProof.b)), mul(ipAuxiliaries.u_x, ipProof.a.mul(ipProof.b)));
        require(eq(ipAuxiliaries.P, cProof), "Inner product equality check failure.");

        return true;
    }

    function assemblePolynomials(uint256[2][] memory f) internal view returns (uint256[2][] memory result) {
        uint256 m = f.length / 2;
        uint256 N = 2 ** m;
        result = new uint256[2][](N);
        for (uint256 i = 0; i < 2; i++) {
            uint256[] memory half = recursivePolynomials(i * m, (i + 1) * m, 1, f);
            for (uint256 j = 0; j < N; j++) {
                result[j][i] = half[j];
            }
        }
    }

    function recursivePolynomials(uint256 baseline, uint256 current, uint256 accum, uint256[2][] memory f) internal view returns (uint256[] memory result) {
        // have to do a bunch of re-allocating because solidity won't let me have something which is internal and also modifies (internal) state. (?)
        uint256 size = 2 ** (current - baseline); // size is at least 2...
        result = new uint256[](size);

        if (current == baseline) {
            result[0] = accum;
            return result;
        }
        current = current - 1;

        uint256[] memory left = recursivePolynomials(baseline, current, accum.mul(f[current][0]), f);
        uint256[] memory right = recursivePolynomials(baseline, current, accum.mul(f[current][1]), f);
        for (uint256 i = 0; i < size / 2; i++) {
            result[i] = left[i];
            result[i + size / 2] = right[i];
        }
    }

    function assembleConvolutions(uint256[2][] memory exponent, G1Point[] memory base) internal view returns (G1Point[2][] memory result) {
        // exponent is two "rows" (actually columns).
        // will return two rows, each of half the length of the exponents;
        // namely, we will return the Hadamards of "base" by the even circular shifts of "exponent"'s rows.
        uint256 size = exponent.length;
        uint256 half = size / 2;
        result = new G1Point[2][](half); // assuming that this is necessary even when return is declared up top

        G1Point[] memory base_fft = fft(base, false);

        uint256[] memory exponent_fft = new uint256[](size);
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < size; j++) {
                exponent_fft[j] = exponent[(size - j) % size][i]; // convolutional flip plus copy
            }

            exponent_fft = fft(exponent_fft);
            G1Point[] memory inverse_fft = new G1Point[](half);
            uint256 compensation = 2;
            compensation = compensation.inv();
            for (uint256 j = 0; j < half; j++) { // Hadamard
                inverse_fft[j] = mul(add(mul(base_fft[j], exponent_fft[j]), mul(base_fft[j + half], exponent_fft[j + half])), compensation);
            }

            inverse_fft = fft(inverse_fft, true);
            for (uint256 j = 0; j < half; j++) {
                result[j][i] = inverse_fft[j];
            }
        }
    }

    function fft(G1Point[] memory input, bool inverse) internal view returns (G1Point[] memory result) {
        uint256 size = input.length;
        if (size == 1) {
            return input;
        }
        require(size % 2 == 0, "Input size is not a power of 2!");

        uint256 omega = UNITY.exp(2**28 / size);
        uint256 compensation = 1;
        if (inverse) {
            omega = omega.inv();
            compensation = 2;
        }
        compensation = compensation.inv();
        G1Point[] memory even = fft(extract(input, 0), inverse);
        G1Point[] memory odd = fft(extract(input, 1), inverse);
        uint256 omega_run = 1;
        result = new G1Point[](size);
        for (uint256 i = 0; i < size / 2; i++) {
            G1Point memory temp = mul(odd[i], omega_run);
            result[i] = mul(add(even[i], temp), compensation);
            result[i + size / 2] = mul(add(even[i], neg(temp)), compensation);
            omega_run = omega_run.mul(omega);
        }
    }

    function extract(G1Point[] memory input, uint256 parity) internal pure returns (G1Point[] memory result) {
        result = new G1Point[](input.length / 2);
        for (uint256 i = 0; i < input.length / 2; i++) {
            result[i] = input[2 * i + parity];
        }
    }

    function fft(uint256[] memory input) internal view returns (uint256[] memory result) {
        uint256 size = input.length;
        if (size == 1) {
            return input;
        }
        require(size % 2 == 0, "Input size is not a power of 2!");

        uint256 omega = UNITY.exp(2**28 / size);
        uint256[] memory even = fft(extract(input, 0));
        uint256[] memory odd = fft(extract(input, 1));
        uint256 omega_run = 1;
        result = new uint256[](size);
        for (uint256 i = 0; i < size / 2; i++) {
            uint256 temp = odd[i].mul(omega_run);
            result[i] = even[i].add(temp);
            result[i + size / 2] = even[i].sub(temp);
            omega_run = omega_run.mul(omega);
        }
    }

    function extract(uint256[] memory input, uint256 parity) internal pure returns (uint256[] memory result) {
        result = new uint256[](input.length / 2);
        for (uint256 i = 0; i < input.length / 2; i++) {
            result[i] = input[2 * i + parity];
        }
    }

    function unserialize(bytes memory arr) internal pure returns (ZetherProof memory proof) {
        proof.BA = G1Point(slice(arr, 0), slice(arr, 32));
        proof.BS = G1Point(slice(arr, 64), slice(arr, 96));
        proof.A = G1Point(slice(arr, 128), slice(arr, 160));
        proof.B = G1Point(slice(arr, 192), slice(arr, 224));
        proof.C = G1Point(slice(arr, 256), slice(arr, 288));
        proof.D = G1Point(slice(arr, 320), slice(arr, 352));
        proof.E = G1Point(slice(arr, 384), slice(arr, 416));
        proof.F = G1Point(slice(arr, 448), slice(arr, 480));

        uint256 m = (arr.length - 2144) / 576;
        proof.CLnG = new G1Point[](m);
        proof.CRnG = new G1Point[](m);
        proof.C_0G = new G1Point[](m);
        proof.DG = new G1Point[](m);
        proof.y_0G = new G1Point[](m);
        proof.gG = new G1Point[](m);
        proof.C_XG = new G1Point[](m);
        proof.y_XG = new G1Point[](m);
        proof.f = new uint256[](2 * m);
        for (uint256 k = 0; k < m; k++) {
            proof.CLnG[k] = G1Point(slice(arr, 512 + k * 64), slice(arr, 544 + k * 64));
            proof.CRnG[k] = G1Point(slice(arr, 512 + (m + k) * 64), slice(arr, 544 + (m + k) * 64));
            proof.C_0G[k] = G1Point(slice(arr, 512 + m * 128 + k * 64), slice(arr, 544 + m * 128 + k * 64));
            proof.DG[k] = G1Point(slice(arr, 512 + m * 192 + k * 64), slice(arr, 544 + m * 192 + k * 64));
            proof.y_0G[k] = G1Point(slice(arr, 512 + m * 256 + k * 64), slice(arr, 544 + m * 256 + k * 64));
            proof.gG[k] = G1Point(slice(arr, 512 + m * 320 + k * 64), slice(arr, 544 + m * 320 + k * 64));
            proof.C_XG[k] = G1Point(slice(arr, 512 + m * 384 + k * 64), slice(arr, 544 + m * 384 + k * 64));
            proof.y_XG[k] = G1Point(slice(arr, 512 + m * 448 + k * 64), slice(arr, 544 + m * 448 + k * 64));
            proof.f[k] = slice(arr, 512 + m * 512 + k * 32);
            proof.f[k + m] = slice(arr, 512 + m * 544 + k * 32);
        }
        uint256 starting = m * 576;
        proof.z_A = slice(arr, 512 + starting);
        proof.z_C = slice(arr, 544 + starting);
        proof.z_E = slice(arr, 576 + starting);

        proof.CPrime = G1Point(slice(arr, 608 + starting), slice(arr, 640 + starting));
        proof.DPrime = G1Point(slice(arr, 672 + starting), slice(arr, 704 + starting));
        proof.CLnPrime = G1Point(slice(arr, 736 + starting), slice(arr, 768 + starting));
        proof.CRnPrime = G1Point(slice(arr, 800 + starting), slice(arr, 832 + starting));

        proof.tCommits = [G1Point(slice(arr, 864 + starting), slice(arr, 896 + starting)), G1Point(slice(arr, 928 + starting), slice(arr, 960 + starting))];
        proof.tHat = slice(arr, 992 + starting);
        proof.tauX = slice(arr, 1024 + starting);
        proof.mu = slice(arr, 1056 + starting);

        proof.c = slice(arr, 1088 + starting);
        proof.s_sk = slice(arr, 1120 + starting);
        proof.s_r = slice(arr, 1152 + starting);
        proof.s_vTransfer = slice(arr, 1184 + starting);
        proof.s_vDiff = slice(arr, 1216 + starting);
        proof.s_nuTransfer = slice(arr, 1248 + starting);
        proof.s_nuDiff = slice(arr, 1280 + starting);

        InnerProductProof memory ipProof;
        for (uint256 i = 0; i < n; i++) {
            ipProof.ls[i] = G1Point(slice(arr, 1312 + starting + i * 64), slice(arr, 1344 + starting + i * 64));
            ipProof.rs[i] = G1Point(slice(arr, 1312 + starting + (n + i) * 64), slice(arr, 1344 + starting + (n + i) * 64));
        }
        ipProof.a = slice(arr, 1312 + starting + n * 128);
        ipProof.b = slice(arr, 1344 + starting + n * 128);
        proof.ipProof = ipProof;

        return proof;
    }

    function addVectors(uint256[m] memory a, uint256[m] memory b) internal pure returns (uint256[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
            result[i] = a[i].add(b[i]);
        }
    }

    function hadamardInv(G1Point[] memory ps, uint256[m] memory ss) internal view returns (G1Point[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
            result[i] = mul(ps[i], ss[i].inv());
        }
    }

    function sumScalars(uint256[m] memory ys) internal pure returns (uint256 result) {
        for (uint256 i = 0; i < m; i++) {
            result = result.add(ys[i]);
        }
    }

    function sumPoints(G1Point[] memory ps) internal view returns (G1Point memory sum) {
        for (uint256 i = 0; i < m; i++) {
            sum = add(sum, ps[i]);
        }
    }

    function commit(G1Point[m] memory ps, uint256[m] memory ss) internal view returns (G1Point memory result) {
        for (uint256 i = 0; i < m; i++) {
            result = add(result, mul(ps[i], ss[i]));
        }
    }

    function powers(uint256 base) internal pure returns (uint256[m] memory powers) {
        powers[0] = 1;
        powers[1] = base;
        for (uint256 i = 2; i < m; i++) {
            powers[i] = powers[i - 1].mul(base);
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

    function add(G1Point memory p1, G1Point memory p2) internal view returns (G1Point memory r) {
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

    function neg(G1Point memory p) internal pure returns (G1Point memory) {
        return G1Point(p.x, FIELD_ORDER - (p.y % FIELD_ORDER)); // p.y should already be reduced mod P?
    }

    function eq(G1Point memory p1, G1Point memory p2) internal pure returns (bool) {
        return p1.x == p2.x && p1.y == p2.y;
    }

    function fieldExp(uint256 base, uint256 exponent) internal view returns (uint256 output) { // warning: mod p, not q
        uint256 order = FIELD_ORDER;
        assembly {
            let m := mload(0x40)
            mstore(m, 0x20)
            mstore(add(m, 0x20), 0x20)
            mstore(add(m, 0x40), 0x20)
            mstore(add(m, 0x60), base)
            mstore(add(m, 0x80), exponent)
            mstore(add(m, 0xa0), order)
            if iszero(staticcall(gas, 0x05, m, 0xc0, m, 0x20)) { // staticcall or call?
                revert(0, 0)
            }
            output := mload(m)
        }
    }

    function mapInto(uint256 seed) internal view returns (G1Point memory) {
        uint256 y;
        while (true) {
            uint256 ySquared = fieldExp(seed, 3) + 3; // addmod instead of add: waste of gas, plus function overhead cost
            y = fieldExp(ySquared, (FIELD_ORDER + 1) / 4);
            if (fieldExp(y, 2) == ySquared) {
                break;
            }
            seed += 1;
        }
        return G1Point(seed, y);
    }

    function mapInto(string memory input) internal view returns (G1Point memory) {
        return mapInto(uint256(keccak256(abi.encodePacked(input))) % FIELD_ORDER);
    }

    function mapInto(string memory input, uint256 i) internal view returns (G1Point memory) {
        return mapInto(uint256(keccak256(abi.encodePacked(input, i))) % FIELD_ORDER);
    }
}
