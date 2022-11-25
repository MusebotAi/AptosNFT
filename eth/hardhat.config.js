require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  networks: {
    hardhat: {
    },
    Sepolia: {
      url: "https://sepolia.infura.io/v3/1bfd81e35caa43c7b701a8c2cd4325c0",
      chainId: 11155111,
      accounts: ["1b2ba08bc81a85ee5f0d3a3c686bb6709214e1b38491c306bcbc38545c82027b"]
    },
    goerli: {
      url: "https://eth-goerli.g.alchemy.com/v2/X5xIi-M6O9Thg9n4TvjYElPE4cXJo8kd",
      accounts: ["1b2ba08bc81a85ee5f0d3a3c686bb6709214e1b38491c306bcbc38545c82027b"]
    }
  },
};
