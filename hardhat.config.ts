import "hardhat-typechain";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-ethers";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-contract-sizer";
import * as dotenv from "dotenv";
dotenv.config({ path: __dirname + "/.env" });

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  //defaultNetwork: "dev",
  networks: {
    hardhat: {
      throwOnTransactionFailures: true,
      throwOnCallFailures: true,
      allowUnlimitedContractSize: true,
    },
    dev: {
      url: "http://localhost:8545",
      gasPrice: 10000000000,
      blockGasLimit: 0x1fffffffffffff,
      accounts: [process.env.PRIV_KEY_LOCAL],
      // accounts: {
      //     mnemonic: process.env.MNEMONIC,
      //     count: 10
      // },
      //saveDeployments: true,
      allowUnlimitedContractSize: true,
    },
    bsctest: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      accounts: [process.env.PRIV_KEY],
      //gas: 2100000,
      //gasPrice: 8000000000,
      gasPrice: 20000000000,
      // gasPrice: 20000000000,
      blockGasLimit: 1000000,
    },
    solanartest: {
      url: "https://api.testnet.solana.com",
      accounts: [process.env.PRIV_KEY],
      gasPrice: 10000000000,
      blockGasLimit: 10000000,
    },
    plgtest: {
      url: "https://polygon-mumbai.g.alchemy.com/v2/TOys_H0HFTfYDDuiwPoW1uwp0XDoOv_e",
      accounts: [process.env.PRIV_KEY],
      gasPrice: 2000000000,
      blockGasLimit: 10000000,
    },
    main: {
      url: "https://bsc-dataseed1.binance.org",
      accounts: [process.env.PRIV_KEY],
      gasPrice: 5100000000,
      blockGasLimit: 1000000,
    },
  },
  etherscan: {
    apiKey: process.env.API_KEY,
  },
};
