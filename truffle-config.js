/**
 * Use this file to configure your truffle project. It's seeded with some
 * common settings for different networks and features like migrations,
 * compilation and testing. Uncomment the ones you need or modify
 * them to suit your project as necessary.
 *
 * More information about configuration can be found at:
 *
 * truffleframework.com/docs/advanced/configuration
 *
 * To deploy via Infura you'll need a wallet provider (like @truffle/hdwallet-provider)
 * to sign your transactions before they're sent to a remote public node. Infura accounts
 * are available for free at: infura.io/register.
 *
 * You'll also need a mnemonic - the twelve word phrase the wallet uses to generate
 * public/private key pairs. If you're publishing your code to GitHub make sure you load this
 * phrase from a file you've .gitignored so it doesn't accidentally become public.
 *
 */

const HDWalletProvider = require("@truffle/hdwallet-provider");
require('dotenv').config();

const Web3 = require("web3");
const web3 = new Web3();

module.exports = {
  /**
   * Networks define how you connect to your ethereum client and let you set the
   * defaults web3 uses to send transactions. If you don't specify one truffle
   * will spin up a development blockchain for you on port 9545 when you
   * run `develop` or `test`. You can ask a truffle command to use a specific
   * network from the command line, e.g
   *
   * $ truffle test --network <network-name>
   */

  contracts_build_directory: "./build",

  networks: {
    mumbai: {
      provider: () => new HDWalletProvider(process.env.MUMBAI_DEPLOYER, process.env.MUMBAI_ENDPOINT),
      network_id: 80001,
      timeoutBlocks: 200,
      skipDryRun: true,
      gas: 6721975,
      gasPrice: 20000000000
    }
  },

  // Set default mocha options here, use special reporters etc.
  mocha: {
    enableTimeouts: false
  },

  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.15",
      settings: {
        optimizer: {
          enabled: true,
          runs: 125
        },
      }
    },
  },
  plugins: [
    "truffle-contract-size"
  ],
  api_keys: {
  }
};
