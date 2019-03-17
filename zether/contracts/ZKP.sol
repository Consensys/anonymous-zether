pragma solidity ^0.5.4;

import './ZetherVerifier.sol';
import './BurnVerifier.sol';

contract ZKP {
    ZetherVerifier zetherVerifier = new ZetherVerifier();
    BurnVerifier burnVerifier = new BurnVerifier();

    function verifyTransfer(bytes32[2][] calldata CL, bytes32[2][] calldata CR, bytes32[2][] calldata L, bytes32[2] calldata R, bytes32[2][] calldata y, uint256 epoch, bytes32[2] calldata u, bytes calldata proof) view external returns (bool) {
        // return zetherVerifier.verify(CL, CR, L, R, y, epoch, u, proof);
        (bool success, bytes memory data) = address(zetherVerifier).staticcall(msg.data);
        if (success && data[3] == 0x01) { // left-to-right indexing for 4-byte response
            return true;
        } else {
            return false;
        } // this should work _even though_ the target function is public, and not external. i have tested...
    }

    function verifyBurn(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata y, uint256 bTransfer, uint256 epoch, bytes32[2] calldata u, bytes calldata proof) view external returns (bool) {
        // return burnVerifier.verify(CLn, CRn, y, bTransfer, epoch, u, proof);
        (bool success, bytes memory data) = address(burnVerifier).staticcall(msg.data);
        if (success && data[3] == 0x01) { // left-to-right indexing for 4-byte response
            return true;
        } else {
            return false;
        }
    }
}
