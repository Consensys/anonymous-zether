pragma solidity ^0.5.3;

contract DummyInterface {
    function run() pure external returns (bytes32);
}

contract ZKP { // basically a wrapper for precompiles...

    DummyInterface verifyTransferInterface = DummyInterface(0x0000000000000000000000000000000000000009);
    DummyInterface verifyBurnInterface = DummyInterface(0x000000000000000000000000000000000000000A);

    function verifyTransfer(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata inL, bytes32[2] calldata outL, bytes32[2] calldata inOutL, bytes32[2] calldata y, bytes32[2] calldata yBar, bytes calldata proof) view external returns (bool) {
        (bool success, bytes memory data) = address(verifyTransferInterface).staticcall(msg.data);
        return verify(success, data);
    }

    function verifyBurn(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata y, uint256 bTransfer, bytes calldata proof) view external returns (bool) {
        (bool success, bytes memory data) = address(verifyBurnInterface).staticcall(msg.data);
        return verify(success, data);
    }

    function verify(bool success, bytes memory data) pure internal returns (bool) {
        if (!success) {
            return false;
        }
        byte b = data[0];
        if (b == 0x00) {
            return false;
        } else if (b == 0x01) {
            return true;
        }
        assert(false);
    }
}
