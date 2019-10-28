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
        uint256 size; // not strictly necessary, but...?
        G1Point A;
        G1Point S;
        G1Point HL;
        G1Point HR;
        G1Point[2] commits;
        uint256 tauX;
        uint256 mu;
        uint256 t;
        AnonProof anonProof;
        SigmaProof sigmaProof;
        InnerProductProof ipProof;
    }

    struct AnonProof {
        G1Point P;
        G1Point Q;
        G1Point U;
        G1Point V;
        G1Point X;
        G1Point Y;
        G1Point CLnG;
        G1Point CRnG;
        G1Point DG;
        G1Point gG;
        G1Point[2][] CG; // flipping the indexing order on this, 'cause...
        G1Point[2][] yG; // assuming this one has the same size..., N / 2 by 2,
        uint256[2][] f; // and that this has size N - 1 by 2.
        uint256 zP;
        uint256 zU;
        uint256 zX;
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
        uint256[3] zs; // [z^2, z^3, z^4]
        uint256[m] twoTimesZSquared;
        uint256 zSum;
        uint256 k;
        G1Point tEval;
        uint256 t;
        uint256 x;
    }

    struct SigmaAuxiliaries {
        uint256 minusC;
        G1Point Ay;
        G1Point AD;
        G1Point gEpoch;
        G1Point Au;
        G1Point ADiff;
        G1Point cCommit;
        G1Point At;
        G1Point[2][] AC;
    }

    struct AnonAuxiliaries {
        uint256 w;
        uint256[2][] f;
        G1Point D2;
        G1Point CLn2;
        G1Point CRn2;
        uint256[2][2] cycler; // should need no inline declaration / initialization. should be pre-allocated
        G1Point[2][] C2;
        G1Point[2][] y2;
        G1Point g2;
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
        ZetherAuxiliaries memory zetherAuxiliaries;
        zetherAuxiliaries.y = uint256(keccak256(abi.encode(uint256(keccak256(abi.encode(statement.CLn, statement.CRn, statement.C, statement.D, statement.y, statement.epoch))).mod(), proof.A, proof.S, proof.HL, proof.HR))).mod();
        zetherAuxiliaries.ys = powers(zetherAuxiliaries.y);
        zetherAuxiliaries.z = uint256(keccak256(abi.encode(zetherAuxiliaries.y))).mod();
        zetherAuxiliaries.zs[0] = zetherAuxiliaries.z.mul(zetherAuxiliaries.z);
        for (uint256 i = 1; i < 3; i++) {
            zetherAuxiliaries.zs[i] = zetherAuxiliaries.zs[i - 1].mul(zetherAuxiliaries.z);
        }
        // zetherAuxiliaries.twoTimesZSquared = times(twos, zetherAuxiliaries.zSquared);
        for (uint256 i = 0; i < m / 2; i++) {
            zetherAuxiliaries.twoTimesZSquared[i] = zetherAuxiliaries.zs[0].mul(2 ** i);
            zetherAuxiliaries.twoTimesZSquared[i + m / 2] = zetherAuxiliaries.zs[1].mul(2 ** i);
        }
        zetherAuxiliaries.x = uint256(keccak256(abi.encode(zetherAuxiliaries.z, proof.commits))).mod();

        zetherAuxiliaries.zSum = zetherAuxiliaries.zs[0].add(zetherAuxiliaries.zs[1]).mul(zetherAuxiliaries.z);
        zetherAuxiliaries.k = sumScalars(zetherAuxiliaries.ys).mul(zetherAuxiliaries.z.sub(zetherAuxiliaries.zs[0])).sub(zetherAuxiliaries.zSum.mul(2 ** (m / 2)).sub(zetherAuxiliaries.zSum));
        zetherAuxiliaries.tEval = add(mul(proof.commits[0], zetherAuxiliaries.x), mul(proof.commits[1], zetherAuxiliaries.x.mul(zetherAuxiliaries.x))); // replace with "commit"?
        zetherAuxiliaries.t = proof.t.sub(zetherAuxiliaries.k);

        // begin anon proof.
        // length equality checks for anonProof members? or during deserialization?
        AnonProof memory anonProof = proof.anonProof;
        AnonAuxiliaries memory anonAuxiliaries;
        G1Point[6] memory letters = [anonProof.P, anonProof.Q, anonProof.U, anonProof.V, anonProof.X, anonProof.Y]; // only purpose is to avoid stacktoodeep
        anonAuxiliaries.w = uint256(keccak256(abi.encode(zetherAuxiliaries.x, letters, anonProof.CLnG, anonProof.CRnG, anonProof.DG, anonProof.gG, anonProof.CG, anonProof.yG))).mod();
        anonAuxiliaries.f = new uint256[2][](proof.size);
        anonAuxiliaries.f[0][0] = anonAuxiliaries.w;
        anonAuxiliaries.f[0][1] = anonAuxiliaries.w;
        for (uint i = 1; i < proof.size; i++) {
            anonAuxiliaries.f[i][0] = anonProof.f[i - 1][0];
            anonAuxiliaries.f[i][1] = anonProof.f[i - 1][1];
            anonAuxiliaries.f[0][0] = anonAuxiliaries.f[0][0].sub(anonAuxiliaries.f[i][0]);
            anonAuxiliaries.f[0][1] = anonAuxiliaries.f[0][1].sub(anonAuxiliaries.f[i][1]);
        }
        G1Point memory temp;
        for (uint256 i = 0; i < proof.size; i++) {
            temp = add(temp, mul(gs[i], anonAuxiliaries.f[i][0]));
            temp = add(temp, mul(hs[i], anonAuxiliaries.f[i][1])); // commutative
        }

        require(eq(add(mul(anonProof.Q, anonAuxiliaries.w), anonProof.P), add(temp, mul(h, anonProof.zP))), "Recovery failure for Q^w * P.");
        for (uint i = 0; i < proof.size; i++) {
            anonAuxiliaries.f[i][0] = anonAuxiliaries.f[i][0].mul(anonAuxiliaries.w.sub(anonAuxiliaries.f[i][0]));
            anonAuxiliaries.f[i][1] = anonAuxiliaries.f[i][1].mul(anonAuxiliaries.w.sub(anonAuxiliaries.f[i][1]));
        }
        temp = G1Point(0, 0);
        for (uint256 i = 0; i < proof.size; i++) { // danger... gs and hs need to be big enough.
            temp = add(temp, mul(gs[i], anonAuxiliaries.f[i][0]));
            temp = add(temp, mul(hs[i], anonAuxiliaries.f[i][1])); // commutative
        }
        require(eq(add(mul(anonProof.U, anonAuxiliaries.w), anonProof.V), add(temp, mul(h, anonProof.zU))), "Recovery failure for U^w * V.");

        anonAuxiliaries.f[0][0] = anonAuxiliaries.w;
        anonAuxiliaries.f[0][1] = anonAuxiliaries.w;
        for (uint i = 1; i < proof.size; i++) { // need to recompute these. contract too large if use another variable
            anonAuxiliaries.f[i][0] = anonProof.f[i - 1][0];
            anonAuxiliaries.f[i][1] = anonProof.f[i - 1][1];
            anonAuxiliaries.f[0][0] = anonAuxiliaries.f[0][0].sub(anonAuxiliaries.f[i][0]);
            anonAuxiliaries.f[0][1] = anonAuxiliaries.f[0][1].sub(anonAuxiliaries.f[i][1]);
        }

        anonAuxiliaries.C2 = assembleConvolutions(anonAuxiliaries.f, statement.C); // will internally include _two_ fourier transforms, and split even / odd, etc.
        anonAuxiliaries.y2 = assembleConvolutions(anonAuxiliaries.f, statement.y);
        anonAuxiliaries.D2 = add(mul(statement.D, anonAuxiliaries.w), neg(anonProof.DG));
        for (uint256 i = 0; i < proof.size / 2; i++) { // order of loops can be switched...
            // could use _two_ further nested loops inside this, but...
            for (uint256 j = 0; j < 2; j++) {
                for (uint256 k = 0; k < 2; k++) {
                    anonAuxiliaries.cycler[k][j] = anonAuxiliaries.cycler[k][j].add(anonAuxiliaries.f[2 * i + k][j]);
                }
                anonAuxiliaries.C2[i][j] = add(anonAuxiliaries.C2[i][j], neg(anonProof.CG[i][j]));
                anonAuxiliaries.y2[i][j] = add(anonAuxiliaries.y2[i][j], neg(anonProof.yG[i][j]));
            }
        }
        // replace the leftmost column with the Hadamard of the left and right columns. just do the multiplication once...
        anonAuxiliaries.cycler[0][0] = anonAuxiliaries.cycler[0][0].mul(anonAuxiliaries.cycler[0][1]);
        anonAuxiliaries.cycler[1][0] = anonAuxiliaries.cycler[1][0].mul(anonAuxiliaries.cycler[1][1]);
        temp = add(mul(gs[0], anonAuxiliaries.cycler[0][0]), mul(hs[0], anonAuxiliaries.cycler[1][0]));

        require(eq(add(mul(anonProof.Y, anonAuxiliaries.w), anonProof.X), add(temp, mul(h, anonProof.zX))), "Index opposite parity check fail.");

        for (uint256 i = 0; i < proof.size; i++) {
            anonAuxiliaries.CLn2 = add(anonAuxiliaries.CLn2, mul(statement.CLn[i], anonAuxiliaries.f[i][0]));
            anonAuxiliaries.CRn2 = add(anonAuxiliaries.CRn2, mul(statement.CRn[i], anonAuxiliaries.f[i][0]));
        }
        anonAuxiliaries.CLn2 = add(anonAuxiliaries.CLn2, neg(anonProof.CLnG));
        anonAuxiliaries.CRn2 = add(anonAuxiliaries.CRn2, neg(anonProof.CRnG));

        anonAuxiliaries.g2 = add(mul(g, anonAuxiliaries.w), neg(anonProof.gG));

        SigmaProof memory sigmaProof = proof.sigmaProof;
        SigmaAuxiliaries memory sigmaAuxiliaries;
        sigmaAuxiliaries.minusC = sigmaProof.c.neg();

        sigmaAuxiliaries.AD = add(mul(anonAuxiliaries.g2, sigmaProof.sR), mul(anonAuxiliaries.D2, sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.Ay = add(mul(anonAuxiliaries.g2, sigmaProof.sX), mul(anonAuxiliaries.y2[0][0], sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.gEpoch = mapInto("Zether", statement.epoch);
        sigmaAuxiliaries.Au = add(mul(sigmaAuxiliaries.gEpoch, sigmaProof.sX), mul(statement.u, sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.ADiff = add(mul(add(anonAuxiliaries.y2[0][0], anonAuxiliaries.y2[0][1]), sigmaProof.sR), mul(add(anonAuxiliaries.C2[0][0], anonAuxiliaries.C2[0][1]), sigmaAuxiliaries.minusC));
        sigmaAuxiliaries.cCommit = add(add(mul(add(mul(anonAuxiliaries.C2[0][0], sigmaProof.c.neg()), mul(anonAuxiliaries.D2, sigmaProof.sX)), zetherAuxiliaries.zs[0]), mul(add(mul(anonAuxiliaries.CLn2, sigmaProof.c), mul(anonAuxiliaries.CRn2, sigmaProof.sX.neg())), zetherAuxiliaries.zs[1])), mul(add(mul(proof.HL, sigmaProof.c), mul(proof.HR, sigmaProof.sX.neg())), zetherAuxiliaries.zs[2].mul(anonAuxiliaries.w)));
        sigmaAuxiliaries.At = add(neg(sigmaAuxiliaries.cCommit), mul(add(add(mul(g, zetherAuxiliaries.t), neg(zetherAuxiliaries.tEval)), mul(h, proof.tauX)), sigmaProof.c.mul(anonAuxiliaries.w)));
        sigmaAuxiliaries.AC = new G1Point[2][](proof.size / 2 - 1);
        for (uint256 i = 1; i < proof.size / 2; i++) {
            sigmaAuxiliaries.AC[i - 1][0] = add(mul(anonAuxiliaries.y2[i][0], sigmaProof.sR), mul(anonAuxiliaries.C2[i][0], sigmaAuxiliaries.minusC));
            sigmaAuxiliaries.AC[i - 1][1] = add(mul(anonAuxiliaries.y2[i][1], sigmaProof.sR), mul(anonAuxiliaries.C2[i][1], sigmaAuxiliaries.minusC));
        }

        uint256 challenge = uint256(keccak256(abi.encode(anonAuxiliaries.w, sigmaAuxiliaries.Ay, sigmaAuxiliaries.AD, sigmaAuxiliaries.Au, sigmaAuxiliaries.ADiff, sigmaAuxiliaries.At, sigmaAuxiliaries.AC))).mod();
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
        G1Point memory cProof = add(add(mul(gTemp, ipProof.a), mul(hTemp, ipProof.b)), mul(ipAuxiliaries.u, ipProof.a.mul(ipProof.b)));
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
        proof.HL = G1Point(slice(arr, 128), slice(arr, 160));
        proof.HR = G1Point(slice(arr, 192), slice(arr, 224));
        proof.commits = [G1Point(slice(arr, 256), slice(arr, 288)), G1Point(slice(arr, 320), slice(arr, 352))];
        proof.t = slice(arr, 384);
        proof.tauX = slice(arr, 416);
        proof.mu = slice(arr, 448);

        SigmaProof memory sigmaProof;
        sigmaProof.c = slice(arr, 480);
        sigmaProof.sX = slice(arr, 512);
        sigmaProof.sR = slice(arr, 544);
        proof.sigmaProof = sigmaProof;

        InnerProductProof memory ipProof;
        for (uint256 i = 0; i < n; i++) {
            ipProof.ls[i] = G1Point(slice(arr, 576 + i * 64), slice(arr, 608 + i * 64));
            ipProof.rs[i] = G1Point(slice(arr, 576 + (n + i) * 64), slice(arr, 608 + (n + i) * 64));
        }
        ipProof.a = slice(arr, 576 + n * 128);
        ipProof.b = slice(arr, 608 + n * 128);
        proof.ipProof = ipProof;

        AnonProof memory anonProof;
        uint256 size = (arr.length - 1408 - 672) / 192;  // warning: this and the below assume that n = 6!!!
        anonProof.P = G1Point(slice(arr, 1408), slice(arr, 1440));
        anonProof.Q = G1Point(slice(arr, 1472), slice(arr, 1504));
        anonProof.U = G1Point(slice(arr, 1536), slice(arr, 1568));
        anonProof.V = G1Point(slice(arr, 1600), slice(arr, 1632));
        anonProof.X = G1Point(slice(arr, 1664), slice(arr, 1696));
        anonProof.Y = G1Point(slice(arr, 1728), slice(arr, 1760));
        anonProof.CLnG = G1Point(slice(arr, 1792), slice(arr, 1824));
        anonProof.CRnG = G1Point(slice(arr, 1856), slice(arr, 1888));
        anonProof.DG = G1Point(slice(arr, 1920), slice(arr, 1952));
        anonProof.gG = G1Point(slice(arr, 1984), slice(arr, 2016));

        anonProof.f = new uint256[2][](size - 1);
        for (uint256 i = 0; i < size - 1; i++) {
            anonProof.f[i][0] = slice(arr, 2048 + 32 * i);
            anonProof.f[i][1] = slice(arr, 2048 + (size - 1 + i) * 32);
        }

        anonProof.CG = new G1Point[2][](size / 2);
        anonProof.yG = new G1Point[2][](size / 2);
        for (uint256 i = 0; i < size / 2; i++) {
            anonProof.CG[i][0] = G1Point(slice(arr, 1984 + (size + i) * 64), slice(arr, 2016 + (size + i) * 64));
            anonProof.CG[i][1] = G1Point(slice(arr, 1984 + size * 96 + i * 64), slice(arr, 2016 + size * 96 + i * 64));
            anonProof.yG[i][0] = G1Point(slice(arr, 1984 + size * 128 + i * 64), slice(arr, 2016 + size * 128 + i * 64));
            anonProof.yG[i][1] = G1Point(slice(arr, 1984 + size * 160 + i * 64), slice(arr, 2016 + size * 160 + i * 64));
            // these are tricky, and can maybe be optimized further?
        }
        proof.size = size;

        anonProof.zP = slice(arr, 1984 + size * 192);
        anonProof.zU = slice(arr, 2016 + size * 192);
        anonProof.zX = slice(arr, 2048 + size * 192);

        proof.anonProof = anonProof;
        return proof;
    }

    function addVectors(uint256[m] memory a, uint256[m] memory b) internal pure returns (uint256[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
            result[i] = a[i].add(b[i]);
        }
    }

    function hadamard_inv(G1Point[] memory ps, uint256[m] memory ss) internal view returns (G1Point[m] memory result) {
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

    function mapInto(uint256 seed) internal view returns (G1Point memory) { // warning: function totally untested!
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

    function mapInto(string memory input) internal view returns (G1Point memory) { // warning: function totally untested!
        return mapInto(uint256(keccak256(abi.encodePacked(input))) % FIELD_ORDER);
    }

    function mapInto(string memory input, uint256 i) internal view returns (G1Point memory) { // warning: function totally untested!
        return mapInto(uint256(keccak256(abi.encodePacked(input, i))) % FIELD_ORDER);
        // ^^^ important: i haven't tested this, i.e. whether it agrees with ProofUtils.paddedHash(input, i) (cf. also the go version)
    }
}
