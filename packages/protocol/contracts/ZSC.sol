// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "./CashToken.sol";
import "./Utils.sol";
import "./InnerProductVerifier.sol";
import "./ZetherVerifier.sol";
import "./BurnVerifier.sol";

contract ZSC {
    using Utils for uint256;
    using Utils for Utils.G1Point;

    CashToken coin;
    ZetherVerifier zetherVerifier;
    BurnVerifier burnVerifier;
    uint256 public epochLength;
    uint256 public fee;

    uint256 constant MAX = 4294967295; // 2^32 - 1 // no sload for constants...!
    mapping(bytes32 => Utils.G1Point[2]) acc; // main account mapping
    mapping(bytes32 => Utils.G1Point[2]) pending; // storage for pending transfers
    mapping(bytes32 => uint256) lastRollOver;
    bytes32[] nonceSet; // would be more natural to use a mapping, but they can't be deleted / reset!
    uint256 lastGlobalUpdate = 0; // will be also used as a proxy for "current epoch", seeing as rollovers will be anticipated
    // not implementing account locking for now...revisit

    event TransferOccurred(Utils.G1Point[] parties, Utils.G1Point beneficiary);
    // arg is still necessary for transfers---not even so much to know when you received a transfer, as to know when you got rolled over.

    constructor(address _coin, address _zether, address _burn, uint256 _epochLength) { // visibiility won't be needed in 7.0
        // epoch length, like block.time, is in _seconds_. 4 is the minimum!!! (To allow a withdrawal to go through.)
        coin = CashToken(_coin);
        zetherVerifier = ZetherVerifier(_zether);
        burnVerifier = BurnVerifier(_burn);
        epochLength = _epochLength;
        fee = zetherVerifier.fee();
        Utils.G1Point memory empty;
        pending[keccak256(abi.encode(empty))][1] = Utils.g(); // "register" the empty account...
    }

    function simulateAccounts(Utils.G1Point[] memory y, uint256 epoch) view public returns (Utils.G1Point[2][] memory accounts) {
        // in this function and others, i have to use public + memory (and hence, a superfluous copy from calldata)
        // only because calldata structs aren't yet supported by solidity. revisit this in the future.
        uint256 size = y.length;
        accounts = new Utils.G1Point[2][](size);
        for (uint256 i = 0; i < size; i++) {
            bytes32 yHash = keccak256(abi.encode(y[i]));
            accounts[i] = acc[yHash];
            if (lastRollOver[yHash] < epoch) {
                Utils.G1Point[2] memory scratch = pending[yHash];
                accounts[i][0] = accounts[i][0].add(scratch[0]);
                accounts[i][1] = accounts[i][1].add(scratch[1]);
            }
        }
    }

    function rollOver(bytes32 yHash) internal {
        uint256 e = block.timestamp / epochLength;
        if (lastRollOver[yHash] < e) {
            Utils.G1Point[2][2] memory scratch = [acc[yHash], pending[yHash]];
            acc[yHash][0] = scratch[0][0].add(scratch[1][0]);
            acc[yHash][1] = scratch[0][1].add(scratch[1][1]);
            // acc[yHash] = scratch[0]; // can't do this---have to do the above instead (and spend 2 sloads / stores)---because "not supported". revisit
            delete pending[yHash]; // pending[yHash] = [Utils.G1Point(0, 0), Utils.G1Point(0, 0)];
            lastRollOver[yHash] = e;
        }
        if (lastGlobalUpdate < e) {
            lastGlobalUpdate = e;
            delete nonceSet;
        }
    }

    function registered(bytes32 yHash) internal view returns (bool) {
        Utils.G1Point memory zero = Utils.G1Point(0, 0);
        Utils.G1Point[2][2] memory scratch = [acc[yHash], pending[yHash]];
        return !(scratch[0][0].eq(zero) && scratch[0][1].eq(zero) && scratch[1][0].eq(zero) && scratch[1][1].eq(zero));
    }

    function register(Utils.G1Point memory y, uint256 c, uint256 s) public {
        // allows y to participate. c, s should be a Schnorr signature on "this"
        Utils.G1Point memory K = Utils.g().mul(s).add(y.mul(c.neg()));
        uint256 challenge = uint256(keccak256(abi.encode(address(this), y, K))).mod();
        require(challenge == c, "Invalid registration signature!");
        bytes32 yHash = keccak256(abi.encode(y));
        require(!registered(yHash), "Account already registered!");
        // pending[yHash] = [y, Utils.g()]; // "not supported" yet, have to do the below
        pending[yHash][0] = y;
        pending[yHash][1] = Utils.g();
    }

    function fund(Utils.G1Point memory y, uint256 bTransfer) public {
        bytes32 yHash = keccak256(abi.encode(y));
        require(registered(yHash), "Account not yet registered.");
        rollOver(yHash);

        require(bTransfer <= MAX, "Deposit amount out of range."); // uint, so other way not necessary?

        Utils.G1Point memory scratch = pending[yHash][0];
        scratch = scratch.add(Utils.g().mul(bTransfer));
        pending[yHash][0] = scratch;
        require(coin.transferFrom(msg.sender, address(this), bTransfer), "Transfer from sender failed.");
        require(coin.balanceOf(address(this)) <= MAX, "Fund pushes contract past maximum value.");
    }

    function transfer(Utils.G1Point[] memory C, Utils.G1Point memory D, Utils.G1Point[] memory y, Utils.G1Point memory u, bytes memory proof, Utils.G1Point memory beneficiary) public {
        uint256 size = y.length;
        Utils.G1Point[] memory CLn = new Utils.G1Point[](size);
        Utils.G1Point[] memory CRn = new Utils.G1Point[](size);
        require(C.length == size, "Input array length mismatch!");

        bytes32 beneficiaryHash = keccak256(abi.encode(beneficiary));
        require(registered(beneficiaryHash), "Miner's account is not yet registered."); // necessary so that receiving a fee can't "backdoor" you into registration.
        rollOver(beneficiaryHash);
        pending[beneficiaryHash][0] = pending[beneficiaryHash][0].add(Utils.g().mul(fee));

        for (uint256 i = 0; i < size; i++) {
            bytes32 yHash = keccak256(abi.encode(y[i]));
            require(registered(yHash), "Account not yet registered.");
            rollOver(yHash);
            Utils.G1Point[2] memory scratch = pending[yHash];
            pending[yHash][0] = scratch[0].add(C[i]);
            pending[yHash][1] = scratch[1].add(D);
            // pending[yHash] = scratch; // can't do this, so have to use 2 sstores _anyway_ (as in above)

            scratch = acc[yHash]; // trying to save an sload, i guess.
            CLn[i] = scratch[0].add(C[i]);
            CRn[i] = scratch[1].add(D);
        }

        bytes32 uHash = keccak256(abi.encode(u));
        for (uint256 i = 0; i < nonceSet.length; i++) {
            require(nonceSet[i] != uHash, "Nonce already seen!");
        }
        nonceSet.push(uHash);

        require(zetherVerifier.verifyTransfer(CLn, CRn, C, D, y, lastGlobalUpdate, u, proof), "Transfer proof verification failed!");

        emit TransferOccurred(y, beneficiary);
    }

    function burn(Utils.G1Point memory y, uint256 bTransfer, Utils.G1Point memory u, bytes memory proof) public {
        bytes32 yHash = keccak256(abi.encode(y));
        require(registered(yHash), "Account not yet registered.");
        rollOver(yHash);

        require(0 <= bTransfer && bTransfer <= MAX, "Transfer amount out of range.");
        Utils.G1Point[2] memory scratch = pending[yHash];
        pending[yHash][0] = scratch[0].add(Utils.g().mul(bTransfer.neg()));

        scratch = acc[yHash]; // simulate debit of acc---just for use in verification, won't be applied
        scratch[0] = scratch[0].add(Utils.g().mul(bTransfer.neg()));
        bytes32 uHash = keccak256(abi.encode(u));
        for (uint256 i = 0; i < nonceSet.length; i++) {
            require(nonceSet[i] != uHash, "Nonce already seen!");
        }
        nonceSet.push(uHash);

        require(burnVerifier.verifyBurn(scratch[0], scratch[1], y, lastGlobalUpdate, u, msg.sender, proof), "Burn proof verification failed!");
        require(coin.transfer(msg.sender, bTransfer), "This shouldn't fail... Something went severely wrong.");
    }
}
