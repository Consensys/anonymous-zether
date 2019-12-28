pragma solidity 0.5.4;
pragma experimental ABIEncoderV2;

library Utils {

    uint256 constant GROUP_ORDER = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 constant FIELD_ORDER = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    function add(uint256 x, uint256 y) internal pure returns (uint256) {
        return addmod(x, y, GROUP_ORDER);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulmod(x, y, GROUP_ORDER);
    }

    function inv(uint256 x) internal view returns (uint256) {
        return exp(x, GROUP_ORDER - 2);
    }

    function mod(uint256 x) internal pure returns (uint256) {
        return x % GROUP_ORDER;
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256) {
        return x >= y ? x - y : GROUP_ORDER - y + x;
    }

    function neg(uint256 x) internal pure returns (uint256) {
        return GROUP_ORDER - x;
    }

    function exp(uint256 base, uint256 exponent) internal view returns (uint256 output) {
        uint256 order = GROUP_ORDER;
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

    function slice(bytes memory input, uint256 start) internal pure returns (uint256 result) { // extracts exactly 32 bytes
        assembly {
            let m := mload(0x40)
            mstore(m, mload(add(add(input, 0x20), start))) // why only 0x20?
            result := mload(m)
        }
    }
}
