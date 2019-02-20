var yBar = ["0x0679ca06b5079fdc9ef4e69b7ee1b49ee06e0930c2ab28476b92ea2f9001a683", "0x04bf8e14e4f31db7fc0650c71c1fd0868b29e6d643a144170adc797a78076e63"]
var bTransfer = 10
var bDiff = 90

var y = alice.me()
var yHash = web3.sha3(y[0].slice(2) + y[1].slice(2), { encoding: 'hex' })
var acc = [[alice.zsc.acc(yHash, 0, 0), alice.zsc.acc(yHash, 0, 1)],[alice.zsc.acc(yHash, 1, 0), alice.zsc.acc(yHash, 1, 1)]]
var pTransfers = [[alice.zsc.pTransfers(yHash, 0, 0), alice.zsc.pTransfers(yHash, 0, 1)],[alice.zsc.pTransfers(yHash, 1, 0), alice.zsc.pTransfers(yHash, 1, 1)]];

var result = zether.proveTransfer(acc[0], acc[1], y, yBar, alice.keypair['x'], 10, 90)

console.log(JSON.stringify(result))
