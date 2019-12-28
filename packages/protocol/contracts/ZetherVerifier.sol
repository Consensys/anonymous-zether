pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "./Utils.sol";
import "./InnerProductVerifier.sol";

contract ZetherVerifier {
    using Utils for uint256;
    using Utils for Utils.G1Point;

    uint256 constant FIELD_ORDER = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint256 constant UNITY = 9334303377689037989442018753807510978357674015322511348041267794643984346845; // primitive 2^28th root of unity modulo GROUP_ORDER (not field!)

    InnerProductVerifier ip;

    struct ZetherStatement {
        Utils.G1Point[] CLn;
        Utils.G1Point[] CRn;
        Utils.G1Point[] C;
        Utils.G1Point D;
        Utils.G1Point[] y;
        uint256 epoch;
        Utils.G1Point u;
    }

    struct ZetherProof {
        Utils.G1Point BA;
        Utils.G1Point BS;
        Utils.G1Point A;
        Utils.G1Point B;
        Utils.G1Point C;
        Utils.G1Point D;
        Utils.G1Point E;
        Utils.G1Point F;

        Utils.G1Point[] CLnG;
        Utils.G1Point[] CRnG;
        Utils.G1Point[] C_0G;
        Utils.G1Point[] DG;
        Utils.G1Point[] y_0G;
        Utils.G1Point[] gG;
        Utils.G1Point[] C_XG;
        Utils.G1Point[] y_XG;

        uint256[] f;
        uint256 z_A;
        uint256 z_C;
        uint256 z_E;

        Utils.G1Point CPrime;
        Utils.G1Point DPrime;
        Utils.G1Point CLnPrime;
        Utils.G1Point CRnPrime;

        Utils.G1Point[2] tCommits;
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

        InnerProductVerifier.InnerProductProof ipProof;
    }

    constructor(address _ip) public {
        ip = InnerProductVerifier(_ip);
    }

    function verifyTransfer(bytes32[2][] memory CLn, bytes32[2][] memory CRn, bytes32[2][] memory C, bytes32[2] memory D, bytes32[2][] memory y, uint256 epoch, bytes32[2] memory u, bytes memory proof) public view returns (bool) {
        ZetherStatement memory statement;
        uint256 size = y.length;

        statement.CLn = new Utils.G1Point[](size);
        statement.CRn = new Utils.G1Point[](size);
        statement.C = new Utils.G1Point[](size);
        statement.y = new Utils.G1Point[](size);
        for (uint256 i = 0; i < size; i++) {
            statement.CLn[i] = Utils.G1Point(uint256(CLn[i][0]), uint256(CLn[i][1]));
            statement.CRn[i] = Utils.G1Point(uint256(CRn[i][0]), uint256(CRn[i][1]));
            statement.C[i] = Utils.G1Point(uint256(C[i][0]), uint256(C[i][1]));
            statement.y[i] = Utils.G1Point(uint256(y[i][0]), uint256(y[i][1]));
        }
        statement.D = Utils.G1Point(uint256(D[0]), uint256(D[1]));
        statement.epoch = epoch;
        statement.u = Utils.G1Point(uint256(u[0]), uint256(u[1]));
        ZetherProof memory zetherProof = unserialize(proof);
        return verify(statement, zetherProof);
    }

    struct ZetherAuxiliaries {
        uint256 y;
        uint256[64] ys;
        uint256 z;
        uint256[2] zs; // [z^2, z^3]
        uint256[64] twoTimesZSquared;
        uint256 zSum;
        uint256 x;
        uint256 t;
        uint256 k;
        Utils.G1Point tEval;
    }

    struct SigmaAuxiliaries {
        uint256 c;
        Utils.G1Point A_y;
        Utils.G1Point A_D;
        Utils.G1Point gEpoch;
        Utils.G1Point A_u;
        Utils.G1Point A_B;
        Utils.G1Point A_X;
        Utils.G1Point c_commit;
        Utils.G1Point A_t;
        Utils.G1Point A_C0;
        Utils.G1Point A_CLn;
        Utils.G1Point A_CPrime;
        Utils.G1Point A_CLnPrime;
    }

    struct AnonAuxiliaries {
        uint256 m;
        uint256 N;
        uint256 v;
        uint256 w;
        uint256 vPow;
        uint256 wPow;
        uint256[2][] f; // could just allocate extra space in the proof?
        uint256[2][] r; // each poly is an array of length N. evaluations of prods
        Utils.G1Point temp;
        Utils.G1Point CLnR;
        Utils.G1Point CRnR;
        Utils.G1Point[2][] CR;
        Utils.G1Point[2][] yR;
        Utils.G1Point C_XR;
        Utils.G1Point y_XR;
        Utils.G1Point gR;
        Utils.G1Point DR;
    }

    struct IPAuxiliaries {
        Utils.G1Point P;
        Utils.G1Point u_x;
        Utils.G1Point[] hPrimes;
        Utils.G1Point hPrimeSum;
        uint256 o;
    }

    function gSum() internal pure returns (Utils.G1Point memory) {
        return Utils.G1Point(0x00715f13ea08d6b51bedcde3599d8e12163e090921309d5aafc9b5bfaadbcda0, 0x27aceab598af7bf3d16ca9d40fe186c489382c21bb9d22b19cb3af8b751b959f);
    }

    function verify(ZetherStatement memory statement, ZetherProof memory proof) internal view returns (bool) {
        uint256 statementHash = uint256(keccak256(abi.encode(statement.CLn, statement.CRn, statement.C, statement.D, statement.y, statement.epoch))).mod();

        AnonAuxiliaries memory anonAuxiliaries;
        anonAuxiliaries.v = uint256(keccak256(abi.encode(statementHash, proof.BA, proof.BS, proof.A, proof.B, proof.C, proof.D, proof.E, proof.F))).mod();
        anonAuxiliaries.w = uint256(keccak256(abi.encode(anonAuxiliaries.v, proof.CLnG, proof.CRnG, proof.C_0G, proof.DG, proof.y_0G, proof.gG, proof.C_XG, proof.y_XG))).mod();
        anonAuxiliaries.m = proof.f.length / 2;
        anonAuxiliaries.N = 2 ** anonAuxiliaries.m;
        anonAuxiliaries.f = new uint256[2][](2 * anonAuxiliaries.m);
        for (uint256 k = 0; k < 2 * anonAuxiliaries.m; k++) {
            anonAuxiliaries.f[k][1] = proof.f[k];
            anonAuxiliaries.f[k][0] = anonAuxiliaries.w.sub(proof.f[k]);
        }

        for (uint256 k = 0; k < 2 * anonAuxiliaries.m; k++) {
            anonAuxiliaries.temp = anonAuxiliaries.temp.add(ip.gs(k).mul(anonAuxiliaries.f[k][1]));
        }
        require(proof.B.mul(anonAuxiliaries.w).add(proof.A).eq(anonAuxiliaries.temp.add(ip.h().mul(proof.z_A))), "Recovery failure for B^w * A.");

        anonAuxiliaries.temp = Utils.G1Point(0, 0);
        for (uint256 k = 0; k < 2 * anonAuxiliaries.m; k++) {
            anonAuxiliaries.temp = anonAuxiliaries.temp.add(ip.gs(k).mul(anonAuxiliaries.f[k][1].mul(anonAuxiliaries.w.sub(anonAuxiliaries.f[k][1]))));
        }
        require(proof.C.mul(anonAuxiliaries.w).add(proof.D).eq(anonAuxiliaries.temp.add(ip.h().mul(proof.z_C))), "Recovery failure for C^w * D.");

        anonAuxiliaries.temp = ip.gs(0).mul(anonAuxiliaries.f[0][1].mul(anonAuxiliaries.f[anonAuxiliaries.m][1])).add(ip.gs(1).mul(anonAuxiliaries.f[0][0].mul(anonAuxiliaries.f[anonAuxiliaries.m][0])));
        require(proof.F.mul(anonAuxiliaries.w).add(proof.E).eq(anonAuxiliaries.temp.add(ip.h().mul(proof.z_E))), "Recovery failure for F^w * E.");

        anonAuxiliaries.r = assemblePolynomials(anonAuxiliaries.f);

        anonAuxiliaries.CR = assembleConvolutions(anonAuxiliaries.r, statement.C);
        anonAuxiliaries.yR = assembleConvolutions(anonAuxiliaries.r, statement.y);
        for (uint256 i = 0; i < anonAuxiliaries.N; i++) {
            anonAuxiliaries.CLnR = anonAuxiliaries.CLnR.add(statement.CLn[i].mul(anonAuxiliaries.r[i][0]));
            anonAuxiliaries.CRnR = anonAuxiliaries.CRnR.add(statement.CRn[i].mul(anonAuxiliaries.r[i][0]));
        }
        anonAuxiliaries.vPow = 1;
        for (uint256 i = 0; i < anonAuxiliaries.N; i++) {
            anonAuxiliaries.C_XR = anonAuxiliaries.C_XR.add(anonAuxiliaries.CR[i / 2][i % 2].mul(anonAuxiliaries.vPow));
            anonAuxiliaries.y_XR = anonAuxiliaries.y_XR.add(anonAuxiliaries.yR[i / 2][i % 2].mul(anonAuxiliaries.vPow));
            if (i > 0) {
                anonAuxiliaries.vPow = anonAuxiliaries.vPow.mul(anonAuxiliaries.v);
            }
        }
        anonAuxiliaries.wPow = 1;
        for (uint256 k = 0; k < anonAuxiliaries.m; k++) {
            anonAuxiliaries.CLnR = anonAuxiliaries.CLnR.add(proof.CLnG[k].mul(anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.CRnR = anonAuxiliaries.CRnR.add(proof.CRnG[k].mul(anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.CR[0][0] = anonAuxiliaries.CR[0][0].add(proof.C_0G[k].mul(anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.DR = anonAuxiliaries.DR.add(proof.DG[k].mul(anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.yR[0][0] = anonAuxiliaries.yR[0][0].add(proof.y_0G[k].mul(anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.gR = anonAuxiliaries.gR.add(proof.gG[k].mul(anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.C_XR = anonAuxiliaries.C_XR.add(proof.C_XG[k].mul(anonAuxiliaries.wPow.neg()));
            anonAuxiliaries.y_XR = anonAuxiliaries.y_XR.add(proof.y_XG[k].mul(anonAuxiliaries.wPow.neg()));

            anonAuxiliaries.wPow = anonAuxiliaries.wPow.mul(anonAuxiliaries.w);
        }
        anonAuxiliaries.DR = anonAuxiliaries.DR.add(statement.D.mul(anonAuxiliaries.wPow));
        anonAuxiliaries.gR = anonAuxiliaries.gR.add(ip.g().mul(anonAuxiliaries.wPow));

        ZetherAuxiliaries memory zetherAuxiliaries;
        zetherAuxiliaries.y = uint256(keccak256(abi.encode(anonAuxiliaries.w, proof.CPrime, proof.DPrime, proof.CLnPrime, proof.CRnPrime))).mod();
        zetherAuxiliaries.ys[0] = 1;
        zetherAuxiliaries.k = 1;
        for (uint256 i = 1; i < 64; i++) {
            zetherAuxiliaries.ys[i] = zetherAuxiliaries.ys[i - 1].mul(zetherAuxiliaries.y);
            zetherAuxiliaries.k = zetherAuxiliaries.k.add(zetherAuxiliaries.ys[i]);
        }
        zetherAuxiliaries.z = uint256(keccak256(abi.encode(zetherAuxiliaries.y))).mod();
        zetherAuxiliaries.zs = [zetherAuxiliaries.z.exp(2), zetherAuxiliaries.z.exp(3)];        
        zetherAuxiliaries.zSum = zetherAuxiliaries.zs[0].add(zetherAuxiliaries.zs[1]).mul(zetherAuxiliaries.z);
        zetherAuxiliaries.k = zetherAuxiliaries.k.mul(zetherAuxiliaries.z.sub(zetherAuxiliaries.zs[0])).sub(zetherAuxiliaries.zSum.mul(2 ** 32).sub(zetherAuxiliaries.zSum));
        zetherAuxiliaries.t = proof.tHat.sub(zetherAuxiliaries.k);
        for (uint256 i = 0; i < 32; i++) {
            zetherAuxiliaries.twoTimesZSquared[i] = zetherAuxiliaries.zs[0].mul(2 ** i);
            zetherAuxiliaries.twoTimesZSquared[i + 32] = zetherAuxiliaries.zs[1].mul(2 ** i);
        }

        zetherAuxiliaries.x = uint256(keccak256(abi.encode(zetherAuxiliaries.z, proof.tCommits))).mod();
        zetherAuxiliaries.tEval = proof.tCommits[0].mul(zetherAuxiliaries.x).add(proof.tCommits[1].mul(zetherAuxiliaries.x.mul(zetherAuxiliaries.x))); // replace with "commit"?

        SigmaAuxiliaries memory sigmaAuxiliaries;
        sigmaAuxiliaries.A_y = anonAuxiliaries.gR.mul(proof.s_sk).add(anonAuxiliaries.yR[0][0].mul(proof.c.neg()));
        sigmaAuxiliaries.A_D = ip.g().mul(proof.s_r).add(statement.D.mul(proof.c.neg())); // add(mul(anonAuxiliaries.gR, proof.s_r), mul(anonAuxiliaries.DR, proof.c.neg()));
        sigmaAuxiliaries.gEpoch = Utils.mapInto("Zether", statement.epoch);
        sigmaAuxiliaries.A_u = sigmaAuxiliaries.gEpoch.mul(proof.s_sk).add(statement.u.mul(proof.c.neg()));
        sigmaAuxiliaries.A_X = anonAuxiliaries.y_XR.mul(proof.s_r).add(anonAuxiliaries.C_XR.mul(proof.c.neg()));
        sigmaAuxiliaries.c_commit = anonAuxiliaries.DR.add(proof.DPrime).mul(proof.s_sk).add(anonAuxiliaries.CR[0][0].add(proof.CPrime).mul(proof.c.neg())).mul(zetherAuxiliaries.zs[0]).add(anonAuxiliaries.CRnR.add(proof.CRnPrime).mul(proof.s_sk).add(anonAuxiliaries.CLnR.add(proof.CLnPrime).mul(proof.c.neg())).mul(zetherAuxiliaries.zs[1]));
        sigmaAuxiliaries.A_t = ip.g().mul(zetherAuxiliaries.t).add(ip.h().mul(proof.tauX)).add(zetherAuxiliaries.tEval.neg()).mul(proof.c.mul(anonAuxiliaries.wPow)).add(sigmaAuxiliaries.c_commit);
        sigmaAuxiliaries.A_C0 = ip.g().mul(proof.s_vTransfer).add(anonAuxiliaries.DR.mul(proof.s_sk).add(anonAuxiliaries.CR[0][0].mul(proof.c.neg())));
        sigmaAuxiliaries.A_CLn = ip.g().mul(proof.s_vDiff).add(anonAuxiliaries.CRnR.mul(proof.s_sk).add(anonAuxiliaries.CLnR.mul(proof.c.neg())));
        sigmaAuxiliaries.A_CPrime = ip.h().mul(proof.s_nuTransfer).add(proof.DPrime.mul(proof.s_sk).add(proof.CPrime.mul(proof.c.neg())));
        sigmaAuxiliaries.A_CLnPrime = ip.h().mul(proof.s_nuDiff).add(proof.CRnPrime.mul(proof.s_sk).add(proof.CLnPrime.mul(proof.c.neg())));

        sigmaAuxiliaries.c = uint256(keccak256(abi.encode(zetherAuxiliaries.x, sigmaAuxiliaries.A_y, sigmaAuxiliaries.A_D, sigmaAuxiliaries.A_u, sigmaAuxiliaries.A_X, sigmaAuxiliaries.A_t, sigmaAuxiliaries.A_C0, sigmaAuxiliaries.A_CLn, sigmaAuxiliaries.A_CPrime, sigmaAuxiliaries.A_CLnPrime))).mod();
        require(sigmaAuxiliaries.c == proof.c, "Sigma protocol challenge equality failure.");

        IPAuxiliaries memory ipAuxiliaries;
        ipAuxiliaries.o = uint256(keccak256(abi.encode(sigmaAuxiliaries.c))).mod();
        ipAuxiliaries.u_x = ip.g().mul(ipAuxiliaries.o);
        ipAuxiliaries.hPrimes = new Utils.G1Point[](64);
        for (uint256 i = 0; i < 64; i++) {
            ipAuxiliaries.hPrimes[i] = ip.hs(i).mul(zetherAuxiliaries.ys[i].inv());
            ipAuxiliaries.hPrimeSum = ipAuxiliaries.hPrimeSum.add(ipAuxiliaries.hPrimes[i].mul(zetherAuxiliaries.ys[i].mul(zetherAuxiliaries.z).add(zetherAuxiliaries.twoTimesZSquared[i])));
        }
        ipAuxiliaries.P = proof.BA.add(proof.BS.mul(zetherAuxiliaries.x)).add(gSum().mul(zetherAuxiliaries.z.neg())).add(ipAuxiliaries.hPrimeSum);
        ipAuxiliaries.P = ipAuxiliaries.P.add(ip.h().mul(proof.mu.neg()));
        ipAuxiliaries.P = ipAuxiliaries.P.add(ipAuxiliaries.u_x.mul(proof.tHat));
        require(ip.verifyInnerProduct(ipAuxiliaries.hPrimes, ipAuxiliaries.u_x, ipAuxiliaries.P, proof.ipProof, ipAuxiliaries.o), "Inner product proof verification failed.");

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

    function assembleConvolutions(uint256[2][] memory exponent, Utils.G1Point[] memory base) internal view returns (Utils.G1Point[2][] memory result) {
        // exponent is two "rows" (actually columns).
        // will return two rows, each of half the length of the exponents;
        // namely, we will return the Hadamards of "base" by the even circular shifts of "exponent"'s rows.
        uint256 size = exponent.length;
        uint256 half = size / 2;
        result = new Utils.G1Point[2][](half); // assuming that this is necessary even when return is declared up top

        Utils.G1Point[] memory base_fft = fft(base, false);

        uint256[] memory exponent_fft = new uint256[](size);
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < size; j++) {
                exponent_fft[j] = exponent[(size - j) % size][i]; // convolutional flip plus copy
            }

            exponent_fft = fft(exponent_fft);
            Utils.G1Point[] memory inverse_fft = new Utils.G1Point[](half);
            uint256 compensation = 2;
            compensation = compensation.inv();
            for (uint256 j = 0; j < half; j++) { // Hadamard
                inverse_fft[j] = base_fft[j].mul(exponent_fft[j]).add(base_fft[j + half].mul(exponent_fft[j + half])).mul(compensation);
            }

            inverse_fft = fft(inverse_fft, true);
            for (uint256 j = 0; j < half; j++) {
                result[j][i] = inverse_fft[j];
            }
        }
    }

    function fft(Utils.G1Point[] memory input, bool inverse) internal view returns (Utils.G1Point[] memory result) {
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
        Utils.G1Point[] memory even = fft(extract(input, 0), inverse);
        Utils.G1Point[] memory odd = fft(extract(input, 1), inverse);
        uint256 omega_run = 1;
        result = new Utils.G1Point[](size);
        for (uint256 i = 0; i < size / 2; i++) {
            Utils.G1Point memory temp = odd[i].mul(omega_run);
            result[i] = even[i].add(temp).mul(compensation);
            result[i + size / 2] = even[i].add(temp.neg()).mul(compensation);
            omega_run = omega_run.mul(omega);
        }
    }

    function extract(Utils.G1Point[] memory input, uint256 parity) internal pure returns (Utils.G1Point[] memory result) {
        result = new Utils.G1Point[](input.length / 2);
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
        proof.BA = Utils.G1Point(Utils.slice(arr, 0), Utils.slice(arr, 32));
        proof.BS = Utils.G1Point(Utils.slice(arr, 64), Utils.slice(arr, 96));
        proof.A = Utils.G1Point(Utils.slice(arr, 128), Utils.slice(arr, 160));
        proof.B = Utils.G1Point(Utils.slice(arr, 192), Utils.slice(arr, 224));
        proof.C = Utils.G1Point(Utils.slice(arr, 256), Utils.slice(arr, 288));
        proof.D = Utils.G1Point(Utils.slice(arr, 320), Utils.slice(arr, 352));
        proof.E = Utils.G1Point(Utils.slice(arr, 384), Utils.slice(arr, 416));
        proof.F = Utils.G1Point(Utils.slice(arr, 448), Utils.slice(arr, 480));

        uint256 m = (arr.length - 2144) / 576;
        proof.CLnG = new Utils.G1Point[](m);
        proof.CRnG = new Utils.G1Point[](m);
        proof.C_0G = new Utils.G1Point[](m);
        proof.DG = new Utils.G1Point[](m);
        proof.y_0G = new Utils.G1Point[](m);
        proof.gG = new Utils.G1Point[](m);
        proof.C_XG = new Utils.G1Point[](m);
        proof.y_XG = new Utils.G1Point[](m);
        proof.f = new uint256[](2 * m);
        for (uint256 k = 0; k < m; k++) {
            proof.CLnG[k] = Utils.G1Point(Utils.slice(arr, 512 + k * 64), Utils.slice(arr, 544 + k * 64));
            proof.CRnG[k] = Utils.G1Point(Utils.slice(arr, 512 + (m + k) * 64), Utils.slice(arr, 544 + (m + k) * 64));
            proof.C_0G[k] = Utils.G1Point(Utils.slice(arr, 512 + m * 128 + k * 64), Utils.slice(arr, 544 + m * 128 + k * 64));
            proof.DG[k] = Utils.G1Point(Utils.slice(arr, 512 + m * 192 + k * 64), Utils.slice(arr, 544 + m * 192 + k * 64));
            proof.y_0G[k] = Utils.G1Point(Utils.slice(arr, 512 + m * 256 + k * 64), Utils.slice(arr, 544 + m * 256 + k * 64));
            proof.gG[k] = Utils.G1Point(Utils.slice(arr, 512 + m * 320 + k * 64), Utils.slice(arr, 544 + m * 320 + k * 64));
            proof.C_XG[k] = Utils.G1Point(Utils.slice(arr, 512 + m * 384 + k * 64), Utils.slice(arr, 544 + m * 384 + k * 64));
            proof.y_XG[k] = Utils.G1Point(Utils.slice(arr, 512 + m * 448 + k * 64), Utils.slice(arr, 544 + m * 448 + k * 64));
            proof.f[k] = Utils.slice(arr, 512 + m * 512 + k * 32);
            proof.f[k + m] = Utils.slice(arr, 512 + m * 544 + k * 32);
        }
        uint256 starting = m * 576;
        proof.z_A = Utils.slice(arr, 512 + starting);
        proof.z_C = Utils.slice(arr, 544 + starting);
        proof.z_E = Utils.slice(arr, 576 + starting);

        proof.CPrime = Utils.G1Point(Utils.slice(arr, 608 + starting), Utils.slice(arr, 640 + starting));
        proof.DPrime = Utils.G1Point(Utils.slice(arr, 672 + starting), Utils.slice(arr, 704 + starting));
        proof.CLnPrime = Utils.G1Point(Utils.slice(arr, 736 + starting), Utils.slice(arr, 768 + starting));
        proof.CRnPrime = Utils.G1Point(Utils.slice(arr, 800 + starting), Utils.slice(arr, 832 + starting));

        proof.tCommits = [Utils.G1Point(Utils.slice(arr, 864 + starting), Utils.slice(arr, 896 + starting)), Utils.G1Point(Utils.slice(arr, 928 + starting), Utils.slice(arr, 960 + starting))];
        proof.tHat = Utils.slice(arr, 992 + starting);
        proof.tauX = Utils.slice(arr, 1024 + starting);
        proof.mu = Utils.slice(arr, 1056 + starting);

        proof.c = Utils.slice(arr, 1088 + starting);
        proof.s_sk = Utils.slice(arr, 1120 + starting);
        proof.s_r = Utils.slice(arr, 1152 + starting);
        proof.s_vTransfer = Utils.slice(arr, 1184 + starting);
        proof.s_vDiff = Utils.slice(arr, 1216 + starting);
        proof.s_nuTransfer = Utils.slice(arr, 1248 + starting);
        proof.s_nuDiff = Utils.slice(arr, 1280 + starting);

        InnerProductVerifier.InnerProductProof memory ipProof;
        ipProof.ls = new Utils.G1Point[](6);
        ipProof.rs = new Utils.G1Point[](6);
        for (uint256 i = 0; i < 6; i++) { // 2^6 = 64.
            ipProof.ls[i] = Utils.G1Point(Utils.slice(arr, 1312 + starting + i * 64), Utils.slice(arr, 1344 + starting + i * 64));
            ipProof.rs[i] = Utils.G1Point(Utils.slice(arr, 1312 + starting + (6 + i) * 64), Utils.slice(arr, 1344 + starting + (6 + i) * 64));
        }
        ipProof.a = Utils.slice(arr, 1312 + starting + 6 * 128);
        ipProof.b = Utils.slice(arr, 1344 + starting + 6 * 128);
        proof.ipProof = ipProof;

        return proof;
    }
}
