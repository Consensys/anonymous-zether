pragma solidity ^0.5.3;

import './ZKP.sol';

contract ERC20Interface {
  function transfer(address to, uint256 value) external returns (bool);

  function transferFrom(address from, address to, uint256 value) public returns (bool);
}

contract ZSC {
    ERC20Interface coin;
    bytes32 public domainHash;
    ZKP zkp = new ZKP();

    uint256 bTotal = 0; // could use erc20.balanceOf(this), but (even static) calls cost gas during EVM execution
    // uint256 constant MAX = 4294967295; // 2^32 - 1 // save an sload, use a literal...
    mapping(bytes32 => bytes32[2][2]) public acc; // main account mapping
    mapping(bytes32 => bytes32[2][2]) public pTransfers; // storage for pending transfers
    mapping(bytes32 => address) public ethAddrs; // used for signing. needs to be public...?
    // not implementing account locking for now...revisit
    mapping(bytes32 => uint256) public ctr;

    event RegistrationOccurred(bytes32[2] registerer, address addr);
    event RollOverOccurred(bytes32[2] roller);
    event FundOccurred(bytes32[2] funder);
    event BurnOccurred(bytes32[2] burner);
    event TransferOccurred(bytes32[2] sender, bytes32[2] recipient);


    constructor(address _coin, uint256 _chainId) public {
        coin = ERC20Interface(_coin);

        bytes32 _domainHash;
        assembly {
            let m := mload(0x40)
            mstore(m, 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f) // "EIP712Domain(string name, string version, uint256 chainId, address verifyingContract)"
            mstore(add(m, 0x20), 0xc9d54de6bfed12ed581fc7d2c1ae5f8778aaf7c177d117fdbb15c71c94be6f88) // name = "ZETHER_QUORUM"
            mstore(add(m, 0x40), 0xae209a0b48f21c054280f2455d32cf309387644879d9acbd8ffc199163811885) // version = "0.0.1"
            mstore(add(m, 0x60), _chainId) // chain id
            mstore(add(m, 0x80), address) // verifying contract
            _domainHash := keccak256(m, 0xa0)
        }
        domainHash = _domainHash;
    }

    function rollOver(bytes32[2] calldata y) external {
        bytes32 yHash = keccak256(abi.encodePacked(y));
        require(msg.sender == ethAddrs[yHash], "No permission to roll over this account.");

        bytes32[2][4] memory scratch = [acc[yHash][0], pTransfers[yHash][0], acc[yHash][1], pTransfers[yHash][1]];
        assembly {
            let result := 1
            let m := mload(0x40)
            mstore(m, mload(mload(scratch)))
            mstore(add(m, 0x20), mload(add(mload(scratch), 0x20)))
            mstore(add(m, 0x40), mload(mload(add(scratch, 0x20))))
            mstore(add(m, 0x60), mload(add(mload(add(scratch, 0x20)), 0x20)))
            result := and(result, call(gas, 0x06, 0, m, 0x80, mload(scratch), 0x40))
            mstore(m, mload(mload(add(scratch, 0x40))))
            mstore(add(m, 0x20), mload(add(mload(add(scratch, 0x40)), 0x20)))
            mstore(add(m, 0x40), mload(mload(add(scratch, 0x60))))
            mstore(add(m, 0x60), mload(add(mload(add(scratch, 0x60)), 0x20)))
            result := and(result, call(gas, 0x06, 0, m, 0x80, mload(add(scratch, 0x40)), 0x40))
            if iszero(result) {
                revert(0, 0)
            }
        }
        acc[yHash] = [scratch[0], scratch[2]];
        pTransfers[yHash] = [[bytes32(0), bytes32(0)], [bytes32(0), bytes32(0)]];
        emit RollOverOccurred(y);
    }

    function register(bytes32[2] calldata y) external {
        bytes32 yHash = keccak256(abi.encodePacked(y));

        require(ctr[yHash] == 0, "Account already registered.");
        ethAddrs[yHash] = msg.sender; // eth address will be _permanently_ bound to y
        // warning: front-running danger. client should verify that he was not front-run before depositing funds to y!
        ctr[yHash] = 1;
        emit RegistrationOccurred(y, msg.sender); // client must use this event callback to confirm.
    }

    function fund(bytes32[2] calldata y, uint256 bTransfer) external {
        bytes32 yHash = keccak256(abi.encodePacked(y));

        // registration check here would be redundant, as any `transferFrom` the 0 address will necessarily fail. save an sload
        require(bTransfer <= 4294967295, "Deposit amount out of range."); // uint, so other way not necessary?
        require(bTransfer + bTotal <= 4294967295, "Fund pushes contract past maximum value.");
        // if pTransfers[yHash] == [0, 0, 0, 0] then an add and a write will be equivalent...
        bytes32[2][2] memory scratch = [[bytes32(0), bytes32(0)], [bytes32(0), bytes32(0)]];
        // won't let me assign this array using literals / casts
        assembly {
            let m := mload(0x40)
            // load bulletproof generator here
            mstore(m, 0x77da99d806abd13c9f15ece5398525119d11e11e9836b2ee7d23f6159ad87d4)
            mstore(add(m, 0x20), 0x1485efa927f2ad41bff567eec88f32fb0a0f706588b4e41a8d587d008b7f875)
            mstore(add(m, 0x40), bTransfer) // b will hopefully be a primitive / literal and not a pointer / address?
            if iszero(call(gas, 0x07, 0, m, 0x60, mload(scratch), 0x40)) {
                revert(0, 0)
            }
        }
        scratch[1] = acc[yHash][0]; // solidity puts this in a weird memory location...?
        assembly {
            let m := mload(0x40)
            mstore(m, mload(mload(scratch)))
            mstore(add(m, 0x20), mload(add(mload(scratch), 0x20)))
            mstore(add(m, 0x40), mload(mload(add(scratch, 0x20))))
            mstore(add(m, 0x60), mload(add(mload(add(scratch, 0x20)), 0x20)))
            if iszero(call(gas, 0x06, 0, m, 0x80, mload(scratch), 0x40)) {
                revert(0, 0)
            }
        }
        acc[yHash][0] = scratch[0];
        require(coin.transferFrom(ethAddrs[yHash], address(this), bTransfer), "Transfer from sender failed");
        // front-running here would be disadvantageous, but still prevent it here by using ethAddrs[yHash] instead of msg.sender
        // also adds flexibility: can later issue messages from arbitrary ethereum accounts.
        bTotal += bTransfer;
        emit FundOccurred(y);
    }

    function verifyTransferSignature(bytes32 yHash, bytes32[2] memory yBar, bytes32[2] memory outL, bytes32[2] memory inL, bytes32[2] memory inOutR, bytes32[3] memory signature) view internal {
        // omitting the proof from the structhash. variable length would be a pain! revisit.
        bytes32 _domainHash = domainHash;
        bytes32 message;
        uint256 count = ctr[yHash];
        bytes memory geth = "\x19Ethereum Signed Message:\n32"; // pain that this is necessary!
        assembly {
            let m := mload(0x40)
            mstore(m, 0x1901)
            mstore(add(m, 0x20), _domainHash)
            mstore(add(m, 0x40), 0xa749c2b2aa979f63aed9ba228701786d8f263ff542fe87003a0ec711252431fe) // keccak256 hash of "ZETHER_TRANSFER_SIGNATURE(bytes32[2] yBar,bytes32[2] inL,bytes32[2] outL, bytes32[2] inOutR,uint256 count)"
            mstore(add(m, 0x60), mload(yBar))
            mstore(add(m, 0x80), mload(add(yBar, 0x20)))
            mstore(add(m, 0x60), keccak256(add(m, 0x60), 0x40))
            mstore(add(m, 0x80), mload(outL))
            mstore(add(m, 0xa0), mload(add(outL, 0x20)))
            mstore(add(m, 0x80), keccak256(add(m, 0x80), 0x40))
            mstore(add(m, 0xa0), mload(inL))
            mstore(add(m, 0xc0), mload(add(inL, 0x20)))
            mstore(add(m, 0xa0), keccak256(add(m, 0xa0), 0x40))
            mstore(add(m, 0xc0), mload(inOutR))
            mstore(add(m, 0xe0), mload(add(inOutR, 0x20)))
            mstore(add(m, 0xc0), keccak256(add(m, 0xc0), 0x40))
            mstore(add(m, 0xe0), count)
            mstore(add(m, 0x40), keccak256(add(m, 0x40), 0xc0))
            message := keccak256(add(m, 0x1e), 0x42)
        }
        address owner = ecrecover(keccak256(abi.encodePacked(geth, message)), uint8(uint256(signature[0])), signature[1], signature[2]);
        require(owner == ethAddrs[yHash], "Signature invalid or for wrong address.");
    }

    function transfer(bytes32[2] calldata outL, bytes32[2] calldata inL, bytes32[2] calldata inOutR, bytes32[2] calldata y, bytes32[2] calldata yBar, bytes calldata proof, bytes32[3] calldata signature) external {
        // wanted to use a struct for these arguments, but more trouble than it's worth. "not yet supported"
        // if public, then must copy to memory twice, instead of once...
        bytes32 yHash = keccak256(abi.encodePacked(y));
        bytes32 yBarHash = keccak256(abi.encodePacked(yBar));

        require(ctr[yBarHash] != 0, "Unregistered recipient!"); // this presents an "opportunistic registration griefing attack"
        // if funds are sent to an unregistered key yBar, a malicious griefer could then register his own ethereum address to yBar before the intended recipient does
        // this would force all subsequent withdrawals from yBar to go to the adversary's address. (though could not be _initiated_ by adv., who doesn't own sk of yBar)
        // owner of yBar could always transfer balance to a new public key yBar2 to which he actually is registered, but this would be a pain and would require him to be alert

        bytes32[2][2] memory scratch = acc[yHash]; // could technically use sload, but... let's not go there.
        assembly {
            let result := 1
            let m := mload(0x40)
            mstore(m, mload(mload(scratch)))
            mstore(add(m, 0x20), mload(add(mload(scratch), 0x20)))
            calldatacopy(add(m, 0x40), 0x04, 0x40) // copy outL to ongoing memory block
            mstore(add(m, 0x80), 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000) // group order - 1
            result := and(result, call(gas, 0x07, 0, add(m, 0x40), 0x60, add(m, 0x40), 0x40))
            result := and(result, call(gas, 0x06, 0, m, 0x80, mload(scratch), 0x40)) // scratch[0] = acc[yHash][0] * inL ^ -1
            mstore(m, mload(mload(add(scratch, 0x20))))
            mstore(add(m, 0x20), mload(add(mload(add(scratch, 0x20)), 0x20)))
            calldatacopy(add(m, 0x40), 0x84, 0x40) // copy inOutR to memory block
            mstore(add(m, 0x80), 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000000) // muls are expensive, but...
            result := and(result, call(gas, 0x07, 0, add(m, 0x40), 0x60, add(m, 0x40), 0x40))
            result := and(result, call(gas, 0x06, 0, m, 0x80, mload(add(scratch, 0x20)), 0x40)) // scratch[1] = acc[yHash][1] * inOutR ^ -1
            if iszero(result) {
                revert(0, 0)
            }
        }

        require(zkp.verifyTransfer(scratch[0], scratch[1], outL, inL, inOutR, y, yBar, proof), "invalid transfer proof");
        verifyTransferSignature(yHash, yBar, outL, inL, inOutR, signature);

        acc[yHash] = scratch; // debit y's balance. make sure this (deep) copies the array
        scratch = pTransfers[yBarHash];
        assembly {
            let result := 1
            let m := mload(0x40)
            mstore(m, mload(mload(scratch)))
            mstore(add(m, 0x20), mload(add(mload(scratch), 0x20)))
            calldatacopy(add(m, 0x40), 0x44, 0x40) // adjoin inL onto running memory block
            result := and(result, call(gas, 0x06, 0, m, 0x80, mload(scratch), 0x40)) // write scratch[0] = acc[yBar][0] * outL
            mstore(m, mload(mload(add(scratch, 0x20))))
            mstore(add(m, 0x20), mload(add(mload(add(scratch, 0x20)), 0x20)))
            calldatacopy(add(m, 0x40), 0x84, 0x40) // adjoin inOutR onto running memory block
            result := and(result, call(gas, 0x06, 0, m, 0x80, mload(add(scratch, 0x20)), 0x40)) // write scratch[1] = acc[yBar][1] * inOutR
            if iszero(result) {
                revert(0, 0)
            }
        }
        pTransfers[yBarHash] = scratch; // credit yBar's balance
        ctr[yHash]++;
        emit TransferOccurred(y, yBar);
    }

    function verifyBurnSignature(bytes32 yHash, uint256 bTransfer, bytes32[3] memory signature) view internal {
        // omitting the proof from the structhash. variable length would be a pain! revisit.
        bytes32 _domainHash = domainHash;
        bytes32 message;
        uint256 count = ctr[yHash];
        bytes memory geth = "\x19Ethereum Signed Message:\n32"; // pain that this is necessary!
        assembly {
            let m := mload(0x40)
            mstore(m, 0x1901)
            mstore(add(m, 0x20), _domainHash)
            mstore(add(m, 0x40), 0x9d72b69945fb58354dfc76c7c1408fc89879b343a0105554190526fc4171d455) // keccak256 hash of "ZETHER_BURN_SIGNATURE(uint256 bTransfer,uint256 count)"
            mstore(add(m, 0x60), bTransfer)
            mstore(add(m, 0x80), count)
            mstore(add(m, 0x40), keccak256(add(m, 0x40), 0x60))
            message := keccak256(add(m, 0x1e), 0x42)
        }
        address owner = ecrecover(keccak256(abi.encodePacked(geth, message)), uint8(uint256(signature[0])), signature[1], signature[2]);
        require(owner == ethAddrs[yHash], "Signature invalid or for wrong address.");
    }

    function burn(bytes32[2] calldata y, uint256 bTransfer, bytes calldata proof, bytes32[3] calldata signature) external {
        bytes32 yHash = keccak256(abi.encodePacked(y));

        require(ctr[yHash] != 0, "Unregistered account!"); // not necessary for safety, but will prevent accidentally withdrawing to the 0 address
        require(0 <= bTransfer && bTransfer <= 4294967295, "Transfer amount out of range");
        bytes32[2][2] memory scratch = acc[yHash]; // could technically use sload, but... let's not go there.
        assembly {
            let result := 1
            let m := mload(0x40)
            mstore(m, mload(mload(scratch)))
            mstore(add(m, 0x20), mload(add(mload(scratch), 0x20)))
            // load bulletproof generator here
            mstore(add(m, 0x40), 0x77da99d806abd13c9f15ece5398525119d11e11e9836b2ee7d23f6159ad87d4) // g_x
            mstore(add(m, 0x60), 0x1485efa927f2ad41bff567eec88f32fb0a0f706588b4e41a8d587d008b7f875) // g_y
            mstore(add(m, 0x80), sub(0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001, bTransfer))
            result := and(result, call(gas, 0x07, 0, add(m, 0x40), 0x60, add(m, 0x40), 0x40))
            result := and(result, call(gas, 0x06, 0, m, 0x80, mload(scratch), 0x40)) // scratch[0] = acc[yHash][0] * g ^ -b, scratch[1] doesn't change
            if iszero(result) {
                revert(0, 0)
            }
        }

        require(zkp.verifyBurn(scratch[0], scratch[1], y, bTransfer, proof), "invalid burn proof");
        verifyBurnSignature(yHash, bTransfer, signature);
        require(coin.transfer(ethAddrs[yHash], bTransfer), "This shouldn't fail... Something went severely wrong");
        // note: change from Zether spec. should use bound address not msg.sender, to prevent "front-running attack".
        acc[yHash] = scratch; // debit y's balance
        ctr[yHash]++;
        bTotal -= bTransfer;
        emit BurnOccurred(y);
    }
}
