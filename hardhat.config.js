require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config(); 

module.exports = {
  solidity: "0.8.24",
  networks: {
    galadriel: {
      chainId: 696969,
      url: "https://devnet.galadriel.com/",
      accounts: [process.env.GALADRIEL_PRIVATE_KEY],
    },
    hardhat: {
      chainId: 1337,
    },
    localhost: {
      chainId: 1337,
      url: "http://127.0.0.1:8545",
      accounts: [process.env.LOCALHOST_PRIVATE_KEY], 
    },
    chiliz_spicy: {
      chainId: 88882,
      url: 'https://spicy-rpc.chiliz.com',
      accounts: [process.env.CHILIZ_SPICY_PRIVATE_KEY],
    },
    morphholesky: {
      chainId: 2810, 
      url: 'https://rpc.morphholesky.net',
      accounts: [process.env.MORPHHOLE_SKY_PRIVATE_KEY], 
    },
  },
};
