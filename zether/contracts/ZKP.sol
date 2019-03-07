pragma solidity ^0.5.4;

contract ZKP {
    function verifyTransfer(bytes32[2][] calldata CL, bytes32[2][] calldata CR, bytes32[2][] calldata L, bytes32[2] calldata R, bytes32[2][] calldata y, uint256 epoch, bytes32[2] calldata u, bytes calldata proof) view external returns (bool) {
        (bool success, bytes memory data) = address(0x09).staticcall(msg.data);
        if (success && data[31] == 0x01) { // indexes left to right...
            return true;
        } else {
            return false;
        }
    }

    function verifyBurn(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata y, uint256 bTransfer, uint256 epoch, bytes32[2] calldata u, bytes calldata proof) view external returns (bool) {
        (bool success, bytes memory data) = address(0x0a).staticcall(msg.data);
        if (success && data[31] == 0x01) { // don't really need to pad java-side, but...?
            return true;
        } else {
            return false;
        }
    }
}
