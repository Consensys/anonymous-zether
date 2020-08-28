module.exports = {
    networks: {
        development: {
            host: "127.0.0.1",
            port: 8545, // ganache
            gasPrice: 0,
            network_id: "*", // Match any network id
            websockets: true,
        }
    },
    compilers: {
        solc: {
            version: "0.7.0",
        }
    }
};
