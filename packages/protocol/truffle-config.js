module.exports = {
    // See <http://truffleframework.com/docs/advanced/configuration>
    // for more about customizing your Truffle configuration!
    networks: {
        develop: {
            host: "127.0.0.1",
            port: 9545,
            gas: 470000000,
            network_id: "*" // Match any network id
        },
        quorum: {
            host: "127.0.0.1",
            port: 22000,
            gasPrice: 0,
            gas: 470000000,
            network_id: "*", // Match any network id
            type: "quorum"
        }
    },
    compilers: {
        solc: {
            version: "0.5.4",
        }
    }
};
