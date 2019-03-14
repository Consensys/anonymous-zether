pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

library alt_bn128 {

    uint256 public constant P = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint256 public constant q = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    struct G1Point {
        uint256 X;
        uint256 Y;
    }

    function add(G1Point memory p1, G1Point memory p2) public view returns (G1Point memory r) {
        assembly {
            let m := mload(0x40)
            mstore(m, mload(p1))
            mstore(add(m, 0x20), mload(add(p1, 0x20)))
            mstore(add(m, 0x40), mload(p2))
            mstore(add(m, 0x60), mload(add(p2, 0x40)))
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
        return G1Point(p.X, P - (p.Y % P)); // p.Y should already be reduced mod P?
    }

    function eq(G1Point memory p1, G1Point memory p2) internal pure returns (bool) {
        return p1.X == p2.X && p1.Y == p2.Y;
    }

    function add(uint256 x, uint256 y) internal pure returns (uint256) {
        return addmod(x, y, q);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulmod(x, y, q);
    }

    function inv(uint256 x) internal view returns (uint256) {
        return exp(x, q - 2);
    }

    function mod(uint256 x) internal pure returns (uint256) {
        return x % q;
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x - y : q - y + x;
    }

    function neg(uint256 x) internal pure returns (uint256) {
        return q - x;
    }

    function exp(uint256 base, uint256 exponent) internal view returns (uint256 output) { // warning: mod p, not q
        uint256 q = q;
        assembly {
            let m := mload(0x40)
            mstore(m, 0x20)
            mstore(add(m, 0x20), 0x20)
            mstore(add(m, 0x40), 0x20)
            mstore(add(m, 0x60), base)
            mstore(add(m, 0x80), exponent)
            mstore(add(m, 0xa0), q)
            if iszero(staticcall(gas, 0x05, m, 0xc0, m, 0x20)) { // staticcall or call?
                revert(0, 0)
            }
            output := mload(m)
        }
    }

    function fieldexp(uint256 base, uint256 exponent) internal view returns (uint256 output) { // warning: mod p, not q
        uint256 P = P;
        assembly {
            let m := mload(0x40)
            mstore(m, 0x20)
            mstore(add(m, 0x20), 0x20)
            mstore(add(m, 0x40), 0x20)
            mstore(add(m, 0x60), base)
            mstore(add(m, 0x80), exponent)
            mstore(add(m, 0xa0), P)
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
            y = fieldexp(ySquared, (P + 1) / 4);
            if (fieldexp(y, 2) == ySquared) {
                break;
            }
            seed += 1;
        }
        return G1Point(seed, y);
    }

    function mapInto(string calldata input) external view returns (G1Point memory) { // warning: function totally untested!
        return mapInto(uint256(keccak256(abi.encodePacked(input))) % P);
    }

    function mapInto(string calldata input, uint256 i) external view returns (G1Point memory) { // warning: function totally untested!
        return mapInto(uint256(keccak256(abi.encodePacked(input, i))) % P);
        // ^^^ important: i haven't tested this, i.e. whether it agrees with ProofUtils.paddedHash(input, i) (cf. also the go version)
    }
}
