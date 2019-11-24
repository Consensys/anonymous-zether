const Web3 = require("web3");

class Provider {
    constructor(address) {
        this.getProvider = () => {
            const provider = new Web3.providers.WebsocketProvider(address);
            return new Promise((resolve, reject) => {
                provider.on("connect", () => resolve(provider));
                provider.on("error", (error) => reject(error)); // don't actually use the error object?
            });
        };
    }
}

module.exports = Provider