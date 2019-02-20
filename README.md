# ButtletProofPOC

This repo contains a Java-based Bulletproofs service as well as a demo for a private funds transfer system (based on Benedikt Bünz's "Zether protocol"), built on top of Quorum.

### Folders in this Repo

[zkp](zkp) is a maven project, which uses our [fork](https://github.com/QuorumEngineering/BulletProofLib) of [Benedikt Bünz's Bulletproofs library](https://github.com/bbuenz/BulletProofLib) as an external dependency. It is designed to be used with a modified version of quorum, currently hosted in the [quorum-mirror](https://github.com/QuorumEngineering/quorum-mirror/tree/api-precompile-rpc).

The [zether](zether) folder contains the ZSC (Zether Smart Contract), as well as scripts to interact with it from the geth console. It can be used to showcase an end-to-end demo.

### User Instructions

##### Prerequisites
- Build the above-linked `api-precompile-rpc` branch of Quorum
- Spin up a Quorum cluster (you may refer to the [7nodes example](https://github.com/jpmorganchase/quorum-examples/tree/master/examples/7nodes))
- Start the Spring application inside the `/zkp` directory of _this_ repo. The easiest way is to import the maven project into an IDE and execute `zkp/src/main/java/zkp/App.java`.
- [Optional] To package everything into a jar file, you could config the `efficientct` jar dependency into the local `.m2` folder, import from there and run `mvn clean install`. After that run `java -jar [path to your jar file]`

##### Demo
In two separate windows, attach to two of the 7 nodes. Let's call them Alice and Bob. The first thing we're going to need is a running ERC20 contract, for which (at least) one of the two participating nodes, Alice let's say, has a balance. I won't go through the steps here; in short, you can compile [OpenZeppelin's ERC20Mintable](https://github.com/OpenZeppelin/openzeppelin-solidity/blob/master/contracts/token/ERC20/ERC20Mintable.sol) contract, deploy it, and then mint yourself some funds. I'll assume that this has already been done, and that the contract resides at the address `erc20mintableAddress = erc20mintable.address`.

In both windows, execute
```javascript
> loadScript('[path to]/BulletProofPOC/zether/tracker.js')
```
In one of these windows (doesn't matter which), deploy the main Zether "ZSC" contract using
```javascript
> var zsc = demo.deployZSC(erc20mintableAddress)
```
Recover this contract in the _other_ window by executing:
```javascript
> var zsc = demo.recoverZSC(zscAddress)
```
where the value `zscAddress` is copied from the value of `zsc.address` in the original window.

Finally, in Alice's window execute
```javascript
> var alice = new tracker(zsc)
```
and in Bob's,
```javascript
> var bob = new tracker(zsc)
```
We're now ready to go.

The API from here on out is extremely simple. The two methods `deposit` and `withdraw` simply take a single numerical parameter. For example, in Alice's window, where `eth.accounts[0]` has funds (and has approved `zsc` to transfer them on its behalf!), you can type
```javascript
> alice.deposit(100)
"Initiating deposit."
> Deposit of 100 was successful. Balance is now 100.
```
or
```javascript
> alice.withdraw(10)
"Initiating withdrawal."
> Withdrawal of 10 was successful. Balance is now 90.
```
To transfer between participants, in Bob's window use
```javascript
> bob.me()
["0x2e9a19152b4c625d05cd36a6dd43f03e54ff0e76cdc01a4aaa1099174c2f327c", "0x27f3c0d1a6eac40021b128f37c4dd943a8e9d48b6f8070a1c72439d2ce8baf9f"]
```
to retrieve his public key and add Bob as a "friend" of Alice, i.e.
```javascript
> alice.friend("Bob", ["0x2e9a19152b4c625d05cd36a6dd43f03e54ff0e76cdc01a4aaa1099174c2f327c", "0x27f3c0d1a6eac40021b128f37c4dd943a8e9d48b6f8070a1c72439d2ce8baf9f"]);
"Friend added."
```
Similarly, copy `alice.me()` and add Alice as a "friend" of Bob. Then, you can use
```javascript
> alice.transfer("Bob", 20)
"Initiating transfer."
> Transfer of 20 was successful. Balance now 70.
```
In Bob's window, you should see:
```javascript
> Transfer received from Alice! New balance is 20.
```
Bob can now transfer his newly received funds to someone else, or withdraw them.

This is all there is to it. Note that all balances and transfer amounts are encrypted, and are not publicly visible. Note also however that at least must transfer must be sent or received in order for the balance to be unknown!
