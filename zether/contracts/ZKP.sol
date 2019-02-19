pragma solidity ^0.5.3;

contract ZKP {

    function verifyTransfer(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata inL, bytes32[2] calldata outL, bytes32[2] calldata inOutR, bytes32[2] calldata y, bytes32[2] calldata yBar, bytes calldata proof) view external returns (bool) {
        (bool success, bytes memory data) = address(0x09).staticcall(msg.data);
        if (success && data[0] == 0x01) {
            return true;
        } else {
            return false;
        }
    }

    function verifyBurn(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata y, uint256 bTransfer, bytes calldata proof) view external returns (bool) {
        (bool success, bytes memory data) = address(0x0a).staticcall(msg.data);
        if (success && data[0] == 0x01) {
            return true;
        } else {
            return false;
        }
    }
}
