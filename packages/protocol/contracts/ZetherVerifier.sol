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

    uint256[m] twos = powers(2);

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
        G1Point A;
        G1Point S;

        G1Point P;
        G1Point Q;
        G1Point U;
        G1Point V;
        G1Point X;
        G1Point Y;
        G1Point CLnG;
        G1Point CRnG;
        G1Point[2][] CG; // flipping the indexing order on this, 'cause...
        G1Point[2][] yG; // assuming this one has the same size..., N / 2 by 2,
        G1Point DG;
        G1Point gG;
        uint256[2][] f; // and that this has size N - 1 by 2.
        uint256 z_P;
        uint256 z_U;
        uint256 z_X;

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
            gs.push(mapInto("G", i));
            hs.push(mapInto("H", i));
        }
    }

    function baseSize() external view returns (uint256 size) {
        return gs.length;
    }

    function extendBase(uint256 size) external payable {
        // unfortunate, but necessary. essentially, we need vector bases of arbitrary (linear) length for large anonsets...
        // could mitigate this by using the logarithmic tricks of Groth and Kohlweiss; see also BCC+15
        // but this would cause problems elsewhere: N log N-sized proofs and N log^2(N) prove / verify time.
        // the increase in proof size is paradoxical: while _f_ will become smaller (log N), you'll need more correction terms
        // thus a linear persistent space overhead is not so bad in the grand scheme, and we deem this acceptable.
        for (uint256 i = gs.length; i < size; i++) {
            gs.push(mapInto("G", i));
            hs.push(mapInto("H", i));
        }
    }

    function verifyTransfer(bytes32[2][] memory CLn, bytes32[2][] memory CRn, bytes32[2][] memory C, bytes32[2] memory D, bytes32[2][] memory y, uint256 epoch, bytes32[2] memory u, bytes memory proof) view public returns (bool) {
        ZetherStatement memory statement;
        uint256 size = y.length;
        require(gs.length >= size, "Inadequate stored vector base! Call extendBase and then try again.");

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
        G1Point c_commit;
        G1Point A_t;
        G1Point[2][] A_C;
        G1Point A_C00;
        G1Point A_CLn;
        G1Point A_CPrime;
        G1Point A_CLnPrime;
    }

    struct AnonAuxiliaries {
        uint256 size;
        uint256 w;
        uint256[2][] f;
        G1Point temp;
        G1Point D2;
        G1Point CLn2;
        G1Point CRn2;
        uint256[2][2] cycler;
        G1Point[2][] C2;
        G1Point[2][] y2;
        G1Point g2;
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
        G1Point[6] memory store = [proof.P, proof.Q, proof.U, proof.V, proof.X, proof.Y]; // for stacktoodeep
        anonAuxiliaries.w = uint256(keccak256(abi.encode(statementHash, proof.A, proof.S, store, proof.CLnG, proof.CRnG, proof.CG, proof.yG, proof.DG, proof.gG))).mod();
        anonAuxiliaries.size = proof.f.length + 1;
        anonAuxiliaries.f = new uint256[2][](anonAuxiliaries.size);
        anonAuxiliaries.f[0][0] = anonAuxiliaries.w;
        anonAuxiliaries.f[0][1] = anonAuxiliaries.w;
        for (uint256 i = 1; i < anonAuxiliaries.size; i++) {
            anonAuxiliaries.f[i][0] = proof.f[i - 1][0];
            anonAuxiliaries.f[i][1] = proof.f[i - 1][1];
            anonAuxiliaries.f[0][0] = anonAuxiliaries.f[0][0].sub(anonAuxiliaries.f[i][0]);
            anonAuxiliaries.f[0][1] = anonAuxiliaries.f[0][1].sub(anonAuxiliaries.f[i][1]);
        }
        for (uint256 i = 0; i < anonAuxiliaries.size; i++) {
            anonAuxiliaries.temp = add(anonAuxiliaries.temp, mul(gs[i], anonAuxiliaries.f[i][0]));
            anonAuxiliaries.temp = add(anonAuxiliaries.temp, mul(hs[i], anonAuxiliaries.f[i][1]));
        }
        require(eq(add(mul(proof.Q, anonAuxiliaries.w), proof.P), add(anonAuxiliaries.temp, mul(h, proof.z_P))), "Recovery failure for Q^w * P.");

        anonAuxiliaries.temp = G1Point(0, 0);
        for (uint256 i = 0; i < anonAuxiliaries.size; i++) { // danger... gs and hs need to be big enough.
            anonAuxiliaries.temp = add(anonAuxiliaries.temp, mul(gs[i], anonAuxiliaries.f[i][0].mul(anonAuxiliaries.w.sub(anonAuxiliaries.f[i][0]))));
            anonAuxiliaries.temp = add(anonAuxiliaries.temp, mul(hs[i], anonAuxiliaries.f[i][1].mul(anonAuxiliaries.w.sub(anonAuxiliaries.f[i][1])))); // commutative
        }
        require(eq(add(mul(proof.U, anonAuxiliaries.w), proof.V), add(anonAuxiliaries.temp, mul(h, proof.z_U))), "Recovery failure for U^w * V.");

        for (uint256 i = 0; i < anonAuxiliaries.size; i++) {
            anonAuxiliaries.CLn2 = add(anonAuxiliaries.CLn2, mul(statement.CLn[i], anonAuxiliaries.f[i][0]));
            anonAuxiliaries.CRn2 = add(anonAuxiliaries.CRn2, mul(statement.CRn[i], anonAuxiliaries.f[i][0]));
        }
        anonAuxiliaries.CLn2 = add(anonAuxiliaries.CLn2, neg(proof.CLnG));
        anonAuxiliaries.CRn2 = add(anonAuxiliaries.CRn2, neg(proof.CRnG));

        anonAuxiliaries.C2 = assembleConvolutions(anonAuxiliaries.f, statement.C); // will internally include _two_ fourier transforms, and split even / odd, etc.
        anonAuxiliaries.y2 = assembleConvolutions(anonAuxiliaries.f, statement.y);

        for (uint256 i = 0; i < anonAuxiliaries.size / 2; i++) { // order of loops can be switched...
            // could use _two_ further nested loops inside this, but...
            for (uint256 j = 0; j < 2; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    anonAuxiliaries.cycler[k][j] = anonAuxiliaries.cycler[k][j].add(anonAuxiliaries.f[2 * i + k][j]);
                }
                anonAuxiliaries.C2[i][j] = add(anonAuxiliaries.C2[i][j], neg(proof.CG[i][j]));
                anonAuxiliaries.y2[i][j] = add(anonAuxiliaries.y2[i][j], neg(proof.yG[i][j]));
            }
        }
        // replace the leftmost column with the Hadamard of the left and right columns. just do the multiplication once...
        anonAuxiliaries.cycler[0][0] = anonAuxiliaries.cycler[0][0].mul(anonAuxiliaries.cycler[0][1]);
        anonAuxiliaries.cycler[1][0] = anonAuxiliaries.cycler[1][0].mul(anonAuxiliaries.cycler[1][1]);
        anonAuxiliaries.temp = add(mul(gs[0], anonAuxiliaries.cycler[0][0]), mul(hs[0], anonAuxiliaries.cycler[1][0]));

        require(eq(add(mul(proof.Y, anonAuxiliaries.w), proof.X), add(anonAuxiliaries.temp, mul(h, proof.z_X))), "Recovery failure for Y^w * X.");

        anonAuxiliaries.D2 = add(mul(statement.D, anonAuxiliaries.w), neg(proof.DG));
        anonAuxiliaries.g2 = add(mul(g, anonAuxiliaries.w), neg(proof.gG));

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
        sigmaAuxiliaries.A_y = add(mul(anonAuxiliaries.g2, proof.s_sk), mul(anonAuxiliaries.y2[0][0], proof.c.neg()));
        sigmaAuxiliaries.A_D = add(mul(anonAuxiliaries.g2, proof.s_r), mul(anonAuxiliaries.D2, proof.c.neg()));
        sigmaAuxiliaries.gEpoch = mapInto("Zether", statement.epoch);
        sigmaAuxiliaries.A_u = add(mul(sigmaAuxiliaries.gEpoch, proof.s_sk), mul(statement.u, proof.c.neg()));
        sigmaAuxiliaries.A_B = add(mul(add(anonAuxiliaries.y2[0][0], anonAuxiliaries.y2[0][1]), proof.s_r), mul(add(anonAuxiliaries.C2[0][0], anonAuxiliaries.C2[0][1]), proof.c.neg()));
        sigmaAuxiliaries.A_C = new G1Point[2][](anonAuxiliaries.size / 2 - 1);
        for (uint256 i = 1; i < anonAuxiliaries.size / 2; i++) {
            sigmaAuxiliaries.A_C[i - 1][0] = add(mul(anonAuxiliaries.y2[i][0], proof.s_r), mul(anonAuxiliaries.C2[i][0], proof.c.neg()));
            sigmaAuxiliaries.A_C[i - 1][1] = add(mul(anonAuxiliaries.y2[i][1], proof.s_r), mul(anonAuxiliaries.C2[i][1], proof.c.neg()));
        }
        sigmaAuxiliaries.c_commit = add(mul(add(mul(add(anonAuxiliaries.D2, proof.DPrime), proof.s_sk), mul(add(anonAuxiliaries.C2[0][0], proof.CPrime), proof.c.neg())), zetherAuxiliaries.zs[0]), mul(add(mul(add(anonAuxiliaries.CRn2, proof.CRnPrime), proof.s_sk), mul(add(anonAuxiliaries.CLn2, proof.CLnPrime), proof.c.neg())), zetherAuxiliaries.zs[1]));
        sigmaAuxiliaries.A_t = add(mul(add(add(mul(g, zetherAuxiliaries.t), mul(h, proof.tauX)), neg(zetherAuxiliaries.tEval)), proof.c.mul(anonAuxiliaries.w)), sigmaAuxiliaries.c_commit);
        sigmaAuxiliaries.A_C00 = add(mul(g, proof.s_vTransfer), add(mul(anonAuxiliaries.D2, proof.s_sk), mul(anonAuxiliaries.C2[0][0], proof.c.neg())));
        sigmaAuxiliaries.A_CLn = add(mul(g, proof.s_vDiff), add(mul(anonAuxiliaries.CRn2, proof.s_sk), mul(anonAuxiliaries.CLn2, proof.c.neg())));
        sigmaAuxiliaries.A_CPrime = add(mul(h, proof.s_nuTransfer), add(mul(proof.DPrime, proof.s_sk), mul(proof.CPrime, proof.c.neg())));
        sigmaAuxiliaries.A_CLnPrime = add(mul(h, proof.s_nuDiff), add(mul(proof.CRnPrime, proof.s_sk), mul(proof.CLnPrime, proof.c.neg())));

        sigmaAuxiliaries.c = uint256(keccak256(abi.encode(zetherAuxiliaries.x, sigmaAuxiliaries.A_y, sigmaAuxiliaries.A_D, sigmaAuxiliaries.A_u, sigmaAuxiliaries.A_B, sigmaAuxiliaries.A_C, sigmaAuxiliaries.A_t, sigmaAuxiliaries.A_C00, sigmaAuxiliaries.A_CLn, sigmaAuxiliaries.A_CPrime, sigmaAuxiliaries.A_CLnPrime))).mod();
        require(sigmaAuxiliaries.c == proof.c, "Sigma protocol challenge equality failure.");

        IPAuxiliaries memory ipAuxiliaries;
        ipAuxiliaries.o = uint256(keccak256(abi.encode(sigmaAuxiliaries.c))).mod();
        ipAuxiliaries.u_x = mul(g, ipAuxiliaries.o);
        ipAuxiliaries.hPrimes = hadamardInv(hs, zetherAuxiliaries.ys);
        ipAuxiliaries.hExp = addVectors(times(zetherAuxiliaries.ys, zetherAuxiliaries.z), zetherAuxiliaries.twoTimesZSquared);
        ipAuxiliaries.P = add(add(add(proof.A, mul(proof.S, zetherAuxiliaries.x)), mul(sumPoints(gs), zetherAuxiliaries.z.neg())), commit(ipAuxiliaries.hPrimes, ipAuxiliaries.hExp));
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
        return result;
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
        proof.A = G1Point(slice(arr, 0), slice(arr, 32));
        proof.S = G1Point(slice(arr, 64), slice(arr, 96));

        proof.P = G1Point(slice(arr, 128), slice(arr, 160));
        proof.Q = G1Point(slice(arr, 192), slice(arr, 224));
        proof.U = G1Point(slice(arr, 256), slice(arr, 288));
        proof.V = G1Point(slice(arr, 320), slice(arr, 352));
        proof.X = G1Point(slice(arr, 384), slice(arr, 416));
        proof.Y = G1Point(slice(arr, 448), slice(arr, 480));
        proof.CLnG = G1Point(slice(arr, 512), slice(arr, 544));
        proof.CRnG = G1Point(slice(arr, 576), slice(arr, 608));
        uint256 size = (arr.length - 2336) / 192; // warning: this and the below assume that n = 6 (i.e. b* and b' are 32 bits).
        proof.CG = new G1Point[2][](size / 2);
        proof.yG = new G1Point[2][](size / 2);
        for (uint256 i = 0; i < size / 2; i++) {
            proof.CG[i][0] = G1Point(slice(arr, 640 + i * 64), slice(arr, 672 + i * 64));
            proof.CG[i][1] = G1Point(slice(arr, 640 + size * 32 + i * 64), slice(arr, 672 + size * 32 + i * 64));
            proof.yG[i][0] = G1Point(slice(arr, 640 + size * 64 + i * 64), slice(arr, 672 + size * 64 + i * 64));
            proof.yG[i][1] = G1Point(slice(arr, 640 + size * 96 + i * 64), slice(arr, 672 + size * 96 + i * 64));
        }
        proof.DG = G1Point(slice(arr, 640 + size * 128), slice(arr, 672 + size * 128));
        proof.gG = G1Point(slice(arr, 704 + size * 128), slice(arr, 736 + size * 128));

        proof.f = new uint256[2][](size - 1);
        for (uint256 i = 0; i < size - 1; i++) {
            proof.f[i][0] = slice(arr, 768 + size * 128 + i * 32);
            proof.f[i][1] = slice(arr, 736 + size * 160 + i * 32); // (size - 1) 32-byte elements above.
        }

        uint256 starting = size * 192;
        proof.z_P = slice(arr, 704 + starting);
        proof.z_U = slice(arr, 736 + starting);
        proof.z_X = slice(arr, 768 + starting);

        proof.CPrime = G1Point(slice(arr, 800 + starting), slice(arr, 832 + starting));
        proof.DPrime = G1Point(slice(arr, 864 + starting), slice(arr, 896 + starting));
        proof.CLnPrime = G1Point(slice(arr, 928 + starting), slice(arr, 960 + starting));
        proof.CRnPrime = G1Point(slice(arr, 992 + starting), slice(arr, 1024 + starting));

        proof.tCommits = [G1Point(slice(arr, 1056 + starting), slice(arr, 1088 + starting)), G1Point(slice(arr, 1120 + starting), slice(arr, 1152 + starting))];
        proof.tHat = slice(arr, 1184 + starting);
        proof.tauX = slice(arr, 1216 + starting);
        proof.mu = slice(arr, 1248 + starting);

        proof.c = slice(arr, 1280 + starting);
        proof.s_sk = slice(arr, 1312 + starting);
        proof.s_r = slice(arr, 1344 + starting);
        proof.s_vTransfer = slice(arr, 1376 + starting);
        proof.s_vDiff = slice(arr, 1408 + starting);
        proof.s_nuTransfer = slice(arr, 1440 + starting);
        proof.s_nuDiff = slice(arr, 1472 + starting);

        InnerProductProof memory ipProof;
        for (uint256 i = 0; i < n; i++) {
            ipProof.ls[i] = G1Point(slice(arr, 1504 + starting + i * 64), slice(arr, 1536 + starting + i * 64));
            ipProof.rs[i] = G1Point(slice(arr, 1504 + starting + (n + i) * 64), slice(arr, 1536 + starting + (n + i) * 64));
        }
        ipProof.a = slice(arr, 1504 + starting + n * 128);
        ipProof.b = slice(arr, 1536 + starting + n * 128);
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
        for (uint256 i = 0; i < m; i++) { // killed a silly initialization with the 0th indexes. [0x00, 0x00] will be treated as the zero point anyway
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
