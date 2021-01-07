# Anonymous Zether

This is a private payment system, an _anonymous_ extension of Bünz, Agrawal, Zamani and Boneh's [Zether protocol](https://eprint.iacr.org/2019/191.pdf).

The authors sketch an anonymous extension in their original manuscript. We develop an explicit proof protocol for this extension, described in the technical paper [AnonZether.pdf](docs/AnonZether.pdf). We also fully implement this anonymous protocol (including verification contracts and a client / front-end with its own proof generator).

## High-level overview

Anonymous Zether is an private value-tracking system, in which an Ethereum smart contract maintains encrypted account balances. Each Zether Smart Contract (ZSC) must, upon deployment, "attach" to some already-deployed ERC-20 contract; once deployed, this contract establishes special "Zether" accounts into / out of which users may _deposit_ or _withdraw_ ERC-20 funds. Having credited funds to a Zether account, its owner may privately send these funds to other Zether accounts, _confidentially_ (transferred amounts are private) and _anonymously_ (identities of transactors are private). Only the owner of each account's secret key may spend its funds, and overdraws are impossible.

To enhance their privacy, users should conduct as much business as possible within the ZSC.

The (anonymous) Zether Smart Contract operates roughly as follows (see the [original Zether paper](https://eprint.iacr.org/2019/191.pdf) for more details). Each account consists of an ElGamal ciphertext, which encrypts the account's balance under its own public key. To send funds, Alice publishes an ordered list of public keys—which contains herself and the recipient, among other arbitrarily chosen parties—together with a corresponding list of ElGamal ciphertexts, which respectively encrypt (under the appropriate public keys) the amounts by which Alice intends to adjust these various accounts' balances. The ZSC applies these adjustments using the homomomorphic property of ElGamal encryption (with "message in the exponent"). Alice finally publishes a zero-knowledge proof which asserts that she knows her own secret key, that she owns enough to cover her deduction, that she deducted funds only from herself, and credited them only to Bob (and by the same amount she debited, no less); she of course also demonstrates that she did not alter those balances other than her own and Bob's. These adjustment ciphertexts—opaque to any outside observer—conceal who sent funds to whom, and how much was sent.

Users need _never_ interact directly with the ZSC; rather, our front-end client streamlines its use.

Our theoretical contribution is a zero-knowledge proof protocol for the anonymous transfer statement (8) of [Bünz, et al.](https://eprint.iacr.org/2019/191.pdf), which moreover has appealing asymptotic performance characteristics; details on our techniques can be found in our [paper](docs/AnonZether.pdf). We also of course provide this implementation.

## Prerequisites

Anonymous Zether can be deployed and tested easily using [Truffle](https://www.trufflesuite.com/truffle) and [Ganache](https://www.trufflesuite.com/ganache).

### Required utilities
* [Yarn](https://yarnpkg.com/en/docs/install#mac-stable), tested with version v1.22.4.
* [Node.js](https://nodejs.org/en/download/), tested with version v12.18.3. (Unfortunately, currently, Node.js v14 has [certain incompatibilities](https://github.com/trufflesuite/ganache-cli/issues/732) with Truffle; you can use `nvm use 12` to temporarily downgrade.)

Run the following commands:
```bash
npm install -g truffle
npm install -g ganache-cli
```
In the main directory, type `yarn`.

## Running Tests

Navigate to the [protocol](./packages/protocol) directory. Type `yarn`.

Now, in one window, type
```bash
ganache-cli --gasPrice 0
```
In a second window, type
```bash
truffle test
```
This command should compile and deploy all necessary contracts, as well as run some example code. You can see this example code in the test file [zsc.js](./packages/protocol/test/zsc.js).

## Detailed usage example
In case you haven't already, navigate to `packages/protocol` directory and run `truffle migrate` to compile the contracts.

In a `node` console, set the variable `__dirname` so that it points to the `packages/protocol` directory. Initialize `web3` in the following way:
```javascript
> Web3 = require('web3');
> const web3 = new Web3('http://localhost:8545');
> const provider = new Web3.providers.WebsocketProvider("ws://localhost:8545");
```
Now, import `Client`:
```javascript
> const Client = require(path.join(__dirname, '../anonymous.js/src/client.js'));
```

The contracts `ZSC` and `CashToken` should be imported in `node` using Truffle's `@truffle/contract` objects:
```javascript
> contract = require("@truffle/contract");
> path = require('path');
> const ZSCJSON = require(path.join(__dirname, 'build/contracts/ZSC.json'));
> const ZSC = contract(ZSCJSON);
> ZSC.setProvider(provider);
> ZSC.deployed();
> let zsc;
> ZSC.at(ZSC.address).then((result) => { zsc = result; });
```
Following the example above, import CashToken:
```javascript
> CashTokenJSON  = require(path.join(__dirname, 'build/contracts/CashToken.json'));
> const CashToken = contract(CashTokenJSON);
> CashToken.setProvider(provider);
> CashToken.deployed();
> let cash;
> CashToken.at(CashToken.address).then((result) => { cash = result; });
```
Before proceeding, you should mint yourself some funds. An example is shown below:
```javascript
> cash.mint(home, 1000, { 'from': home });
> cash.approve(zsc.address, 1000, { 'from': home });
```
Let's assume now that, in four separate `node` consoles, you've imported `Client` and initialized `web3` to an appropriate provider in this way. In each window, type:
```javascript
> let home;
> web3.eth.getAccounts().then((accounts) => { home = accounts[accounts.length - 1]; });
```
to assign the address of an unlocked account to the variable `home`.

In the first window, Alice's let's say, execute:
```javascript
> const alice = new Client(web3, zsc.contract, home);
> alice.register();
Promise { <pending> }
Registration submitted (txHash = "0xe4295b5116eb1fe6c40a40352f4bf609041f93e763b5b27bd28c866f3f4ce2b2").
Registration successful.
```
and in Bob's,
```javascript
> const bob = new Client(web3, zsc.contract, home);
> bob.register();
```

The two functions `deposit` and `withdraw` take a single numerical parameter. For example, in Alice's window, type:
```javascript
> alice.deposit(100);
Initiating deposit.
Promise { <pending> }
Deposit submitted (txHash = "0xa6e4c2d415dda9402c6b20a6b1f374939f847c00d7c0f206200142597ff5be7e").
Deposit of 100 was successful. Balance now 100.
```
Now, type:
```javascript
> alice.withdraw(10);
Initiating withdrawal.
Promise { <pending> }
Withdrawal submitted (txHash = "0xd7cd5de1680594da89823a18c0b74716b6953e23fe60056cc074df75e94c92c5").
Withdrawal of 10 was successful. Balance now 90.
```
In Bob's window, use
```javascript
> bob.account.public();
[
  '0x17f5f0daab7218a462dea5f04d47c9db95497833381f502560486d4019aec495',
  '0x0957b7a0ec24a779f991ea645366b27fe3e93e996f3e7936bdcfb7b18d41a945'
]
```
to retrieve his public key and add Bob as a "friend" of Alice, i.e.
```javascript
> alice.friends.add("Bob", ['0x17f5f0daab7218a462dea5f04d47c9db95497833381f502560486d4019aec495', '0x0957b7a0ec24a779f991ea645366b27fe3e93e996f3e7936bdcfb7b18d41a945']);
'Friend added.'
```
You can now do:
```javascript
> alice.transfer("Bob", 20);
Initiating transfer.
Promise { <pending> }
Transfer submitted (txHash = "0x4c0631483e6ea89d2068c90d5a2f9fa42ad12a102650ff80b887542e18e1d988").
Transfer of 20 was successful. Balance now 70.
```
In Bob's window, you should see:
```javascript
Transfer of 20 received! Balance now 20.
```
You can also add Alice, Carol and Dave as friends of Bob. Now, you can try:
```javascript
> bob.transfer("Alice", 10, ["Carol", "Dave"]);
Initiating transfer.
Promise { <pending> }
Transfer submitted (txHash = "0x9b3f51f3511c6797789862ce745a81d5bdfb00304831a8f25cc8554ea7597860").
Transfer of 10 was successful. Balance now 10.
```
The meaning of this syntax is that Carol and Dave are being included, along with Bob and Alice, in Bob's transaction's _anonymity set_. As a consequence, _no outside observer_ will be able to distinguish, among the four participants, who sent funds, who received funds, and how much was transferred. The account balances of all four participants are also private.

In fact, you can see for yourself the perspective of Eve—an eavesdropper, let's say. In a new window (if you want), execute:
```javascript
> let inputs;
> zsc.contract._jsonInterface.forEach((element) => { if (element['name'] == "transfer") inputs = element['inputs']; });
> let parsed;
> web3.eth.getTransaction('0x9b3f51f3511c6797789862ce745a81d5bdfb00304831a8f25cc8554ea7597860').then((transaction) => { parsed = web3.eth.abi.decodeParameters(inputs, "0x" + transaction.input.slice(10)); });
```
You will see a bunch of fields; in particular, `parsed['y']` will contain the list of public keys, while `parsed['C']`, `parsed['D']` and `parsed['proof']` will contain further bytes which reveal nothing about the transaction.

Anonymous Zether also supports native transaction fees. The idea is that you can circumvent the "gas linkability" issue by submitting each new transaction from a fresh, randomly generated Ethereum address, and furthermore specifying a gas price of 0. By routing a "tip" to a miner's Zether account, you may induce the miner to process your transaction anyway (see "Paying gas in ZTH through economic abstraction", Appendix F of the [original Zether paper](https://eprint.iacr.org/2019/191.pdf)). To do this, change the value at [this line](./packages/protocol/contracts/ZetherVerifier.sol#L16) before deploying, for example to 1. Finally, include the miner's Zether account as a 4th parameter in your `transfer` call. For example:
```javascript
> bob.transfer("Alice", 10, ["Carol", "Dave"], "Miner")
```
In the miner's console, you should see:
```javascript
> Fee of 1 received! Balance now 1.
