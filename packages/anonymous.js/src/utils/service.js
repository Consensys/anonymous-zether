const axios = require('axios');
const baseURL = "http://localhost:8080"
const bn128 = require('./utils/bn128.js');

const service = {};

service.proveTransfer = (CL, CR, y, epoch, x, r, bTransfer, bDiff, index, callback) => {
    const params = {
        'CL': "0x" + CL.map((point) => point[0].slice(2) + point[1].slice(2)).join(''),
        'CR': "0x" + CR.map((point) => point[0].slice(2) + point[1].slice(2)).join(''),
        'y': "0x" + y.map((point) => point[0].slice(2) + point[1].slice(2)).join(''),
        'epoch': bn128.toString(new BN(epoch)),
        x,
        'r': bn128.toString(r),
        'bTransfer': bn128.toString(new BN(bTransfer)),
        'bDiff': bn128.toString(new BN(bDiff)),
        'outIndex': bn128.toString(index[0]),
        'inIndex': bn128.toString(index[1])
    }
    axios.get(baseURL + "/prove-transfer", { params }).then((result) => {
        callback(result);
    });
}

service.proveBurn = (CL, CR, y, bTransfer, epoch, x, bDiff, callback) => {
    const params = {
        'CL': "0x" + CL[0].slice(2) + CL[1].slice(2),
        'CR': "0x" + CR[0].slice(2) + CR[1].slice(2),
        'y': "0x" + y[0].slice(2) + y[1].slice(2),
        'epoch': bn128.toString(new BN(epoch)),
        x,
        'bDiff': bn128.toString(new BN(bDiff)),
    }
    axios.get(baseURL + "/prove-burn", { params }).then((result) => {
        callback(result);
    });
}

module.exports = service;