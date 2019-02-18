pragma solidity ^0.5.3;

contract ZKP {

  function MergeBytes(bytes memory a, bytes memory b) internal pure returns (bytes memory c) {
    // Store the length of the first array
    uint alen = a.length;
    // Store the length of BOTH arrays
    uint totallen = alen + b.length;
    // Count the loops required for array a (sets of 32 bytes)
    uint loopsa = (a.length + 31) / 32;
    // Count the loops required for array b (sets of 32 bytes)
    uint loopsb = (b.length + 31) / 32;
    assembly {
        let m := mload(0x40)
        // Load the length of both arrays to the head of the new bytes array
        mstore(m, totallen)
        // Add the contents of a to the array
        for {  let i := 0 } lt(i, loopsa) { i := add(1, i) } { mstore(add(m, mul(32, add(1, i))), mload(add(a, mul(32, add(1, i))))) }
        // Add the contents of b to the array
        for {  let i := 0 } lt(i, loopsb) { i := add(1, i) } { mstore(add(m, add(mul(32, add(1, i)), alen)), mload(add(b, mul(32, add(1, i))))) }
        mstore(0x40, add(m, add(32, totallen)))
        c := m
    }
  }

  /* function test(bytes32[2] calldata input1, uint256 bTransfer, bytes calldata input2) view external returns (bool) {
    bytes memory i = MergeBytes(abi.encodePacked(input1[0], input1[1], bTransfer), input2);
    uint[1] memory k;
    assembly {
      // gas, address, input, input length, output, output length
      // length is in bytes
      if iszero(staticcall(not(0), 0x0a, i, 0x100, k, 0x20)) {
        revert(0, 0)
      }
    }
    if (k[0] == 1){
      return true;
    } else {
      return false;
    }
  } */

  function verifyTransfer(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata inL, bytes32[2] calldata outL, bytes32[2] calldata inOutR, bytes32[2] calldata y, bytes32[2] calldata yBar, bytes calldata proof) view external returns (bool) {
    bytes memory i = MergeBytes(abi.encodePacked(abi.encodePacked(CLn[0], CLn[1], CRn[0], CRn[1], inL[0], inL[1], outL[0], outL[1]), inOutR[0], inOutR[1], y[0], y[1], yBar[0], yBar[1]), proof);
    uint[1] memory k;
    assembly {
      // gas, address, input, input length, output, output length
      // length is in bytes, length must be larger than total input length...
      if iszero(staticcall(not(0), 0x09, i, 0x1000, k, 0x20)) {
        revert(0, 0)
      }
    }
    if (k[0] == 1){
      return true;
    } else {
      return false;
    }
  }

  function verifyBurn(bytes32[2] calldata CLn, bytes32[2] calldata CRn, bytes32[2] calldata y, uint256 bTransfer, bytes calldata proof) view external returns (bool) {
    bytes memory i = MergeBytes(abi.encodePacked(CLn[0], CLn[1], CRn[0], CRn[1], y[0], y[1], bTransfer), proof);
    uint[1] memory k;
    assembly {
      // gas, address, input, input length, output, output length
      // length is in bytes, length must be larger than total input length...
      if iszero(staticcall(not(0), 0x0a, i, 0x1000, k, 0x20)) {
        revert(0, 0)
      }
    }
    if (k[0] == 1){
      return true;
    } else {
      return false;
    }
  }

}
