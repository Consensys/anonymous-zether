pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

import "./Utils.sol";

contract BurnVerifier {
    using Utils for uint256;

    uint256 constant m = 32;
    uint256 constant n = 5;
    uint256 constant FIELD_ORDER = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    G1Point[m] gs;
    G1Point[m] hs;
    G1Point g;
    G1Point h;

    uint256[m] twos = powers(2); // how much is this actually used?

    struct BurnStatement {
        G1Point CLn;
        G1Point CRn;
        G1Point y;
        uint256 bTransfer;
        uint256 epoch; // or uint8?
        address sender;
        G1Point u;
    }

    struct BurnProof {
        G1Point A;
        G1Point S;

        G1Point CLnPrime;
        G1Point CRnPrime;

        G1Point[2] tCommits;
        uint256 tHat;
        uint256 tauX;
        uint256 mu;

        uint256 c;
        uint256 s_sk;
        uint256 s_vDiff;
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
            gs[i] = mapInto("G", i);
            hs[i] = mapInto("H", i);
        }
    } // will it be more expensive later on to sload these than to recompute them?

    function verifyBurn(bytes32[2] memory CLn, bytes32[2] memory CRn, bytes32[2] memory y, uint256 bTransfer, uint256 epoch, bytes32[2] memory u, address sender, bytes memory proof) view public returns (bool) {
        BurnStatement memory statement; // WARNING: if this is called directly in the console,
        // and your strings are less than 64 characters, they will be padded on the right, not the left. should hopefully not be an issue,
        // as this will typically be called simply by the other contract. still though, beware
        statement.CLn = G1Point(uint256(CLn[0]), uint256(CLn[1]));
        statement.CRn = G1Point(uint256(CRn[0]), uint256(CRn[1]));
        statement.y = G1Point(uint256(y[0]), uint256(y[1]));
        statement.bTransfer = bTransfer;
        statement.epoch = epoch;
        statement.u = G1Point(uint256(u[0]), uint256(u[1]));
        statement.sender = sender;
        BurnProof memory burnProof = unserialize(proof);
        return verify(statement, burnProof);
    }

    struct BurnAuxiliaries {
        uint256 y;
        uint256[m] ys;
        uint256 z;
        uint256[1] zs; // silly. just to match zether.
        uint256 zSum;
        uint256[m] twoTimesZSquared;
        uint256 x;
        uint256 t;
        uint256 k;
        G1Point tEval;
    }

    struct SigmaAuxiliaries {
        uint256 c;
        G1Point A_y;
        G1Point gEpoch;
        G1Point A_u;
        G1Point c_commit;
        G1Point A_t;
        G1Point A_CLn;
        G1Point A_CLnPrime;
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

    function verify(BurnStatement memory statement, BurnProof memory proof) view internal returns (bool) {
        uint256 statementHash = uint256(keccak256(abi.encode(statement.CLn, statement.CRn, statement.y, statement.bTransfer, statement.epoch, statement.sender))).mod(); // stacktoodeep?

        BurnAuxiliaries memory burnAuxiliaries;
        burnAuxiliaries.y = uint256(keccak256(abi.encode(statementHash, proof.A, proof.S, proof.CLnPrime, proof.CRnPrime))).mod();
        burnAuxiliaries.ys = powers(burnAuxiliaries.y);
        burnAuxiliaries.z = uint256(keccak256(abi.encode(burnAuxiliaries.y))).mod();
        burnAuxiliaries.zs = [burnAuxiliaries.z.exp(2)];
        burnAuxiliaries.zSum = burnAuxiliaries.zs[0].mul(burnAuxiliaries.z); // trivial sum
        burnAuxiliaries.k = sumScalars(burnAuxiliaries.ys).mul(burnAuxiliaries.z.sub(burnAuxiliaries.zs[0])).sub(burnAuxiliaries.zSum.mul(2 ** m).sub(burnAuxiliaries.zSum));
        burnAuxiliaries.t = proof.tHat.sub(burnAuxiliaries.k);
        burnAuxiliaries.twoTimesZSquared = times(twos, burnAuxiliaries.zs[0]);

        burnAuxiliaries.x = uint256(keccak256(abi.encode(burnAuxiliaries.z, proof.tCommits))).mod();
        burnAuxiliaries.tEval = add(mul(proof.tCommits[0], burnAuxiliaries.x), mul(proof.tCommits[1], burnAuxiliaries.x.mul(burnAuxiliaries.x))); // replace with "commit"?

        SigmaAuxiliaries memory sigmaAuxiliaries;
        sigmaAuxiliaries.A_y = add(mul(g, proof.s_sk), mul(statement.y, proof.c.neg()));
        sigmaAuxiliaries.gEpoch = mapInto("Zether", statement.epoch);
        sigmaAuxiliaries.A_u = add(mul(sigmaAuxiliaries.gEpoch, proof.s_sk), mul(statement.u, proof.c.neg()));
        sigmaAuxiliaries.c_commit = mul(add(mul(add(statement.CRn, proof.CRnPrime), proof.s_sk), mul(add(statement.CLn, proof.CLnPrime), proof.c.neg())), burnAuxiliaries.zs[0]);
        sigmaAuxiliaries.A_t = add(mul(add(add(mul(g, burnAuxiliaries.t), mul(h, proof.tauX)), neg(burnAuxiliaries.tEval)), proof.c), sigmaAuxiliaries.c_commit);
        sigmaAuxiliaries.A_CLn = add(mul(g, proof.s_vDiff), add(mul(statement.CRn, proof.s_sk), mul(statement.CLn, proof.c.neg())));
        sigmaAuxiliaries.A_CLnPrime = add(mul(h, proof.s_nuDiff), add(mul(proof.CRnPrime, proof.s_sk), mul(proof.CLnPrime, proof.c.neg())));

        sigmaAuxiliaries.c = uint256(keccak256(abi.encode(burnAuxiliaries.x, sigmaAuxiliaries.A_y, sigmaAuxiliaries.A_u, sigmaAuxiliaries.A_t, sigmaAuxiliaries.A_CLn, sigmaAuxiliaries.A_CLnPrime))).mod();
        require(sigmaAuxiliaries.c == proof.c, "Sigma protocol challenge equality failure.");

        IPAuxiliaries memory ipAuxiliaries;
        ipAuxiliaries.o = uint256(keccak256(abi.encode(sigmaAuxiliaries.c))).mod();
        ipAuxiliaries.u_x = mul(g, ipAuxiliaries.o);
        ipAuxiliaries.hPrimes = hadamardInv(hs, burnAuxiliaries.ys);
        ipAuxiliaries.hExp = addVectors(times(burnAuxiliaries.ys, burnAuxiliaries.z), burnAuxiliaries.twoTimesZSquared);
        ipAuxiliaries.P = add(add(add(proof.A, mul(proof.S, burnAuxiliaries.x)), mul(sumPoints(gs), burnAuxiliaries.z.neg())), commit(ipAuxiliaries.hPrimes, ipAuxiliaries.hExp));
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

    function multiExpGs(uint256[m] memory ss) internal view returns (G1Point memory result) {
        for (uint256 i = 0; i < m; i++) {
            result = add(result, mul(gs[i], ss[i]));
        }
    }

    function multiExpHsInversed(uint256[m] memory ss, G1Point[m] memory hs) internal view returns (G1Point memory result) {
        for (uint256 i = 0; i < m; i++) {
            result = add(result, mul(hs[i], ss[m - 1 - i]));
        }
    }

    function unserialize(bytes memory arr) internal pure returns (BurnProof memory proof) {
        proof.A = G1Point(slice(arr, 0), slice(arr, 32));
        proof.S = G1Point(slice(arr, 64), slice(arr, 96));

        proof.CLnPrime = G1Point(slice(arr, 128), slice(arr, 160));
        proof.CRnPrime = G1Point(slice(arr, 192), slice(arr, 224));

        proof.tCommits = [G1Point(slice(arr, 256), slice(arr, 288)), G1Point(slice(arr, 320), slice(arr, 352))];
        proof.tHat = slice(arr, 384);
        proof.tauX = slice(arr, 416);
        proof.mu = slice(arr, 448);

        proof.c = slice(arr, 480);
        proof.s_sk = slice(arr, 512);
        proof.s_vDiff = slice(arr, 544);
        proof.s_nuDiff = slice(arr, 576);

        InnerProductProof memory ipProof;
        for (uint256 i = 0; i < n; i++) {
            ipProof.ls[i] = G1Point(slice(arr, 608 + i * 64), slice(arr, 640 + i * 64));
            ipProof.rs[i] = G1Point(slice(arr, 608 + (n + i) * 64), slice(arr, 640 + (n + i) * 64));
        }
        ipProof.a = slice(arr, 608 + n * 128);
        ipProof.b = slice(arr, 640 + n * 128);
        proof.ipProof = ipProof;

        return proof;
    }

    function addVectors(uint256[m] memory a, uint256[m] memory b) internal pure returns (uint256[m] memory result) {
        for (uint256 i = 0; i < m; i++) {
            result[i] = a[i].add(b[i]);
        }
    }

    function hadamardInv(G1Point[m] memory ps, uint256[m] memory ss) internal view returns (G1Point[m] memory result) {
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
