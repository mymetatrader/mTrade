const BigNumber = require('bignumber.js');
const MTTPriceAggregator_Contract = artifacts.require("MTTPriceAggregator");
var _linkToken = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB";
var _tokenDaiLp = "0xc1ff5d622aebabd51409e01df4461936b0eb4e43";
var _twapInterval = 3600;
var _storageT = "0xeE0b00B8FcA717eE6cD97F3CBAb50D3Ec89adF6F";
var _pairsStorage = "0x048cc9EDd7428197c3ece09D86033D601D2596A9";
var _linkPriceFeed = "0x1c2252aeed50e0c9b64bdff2735ee3c932f5c408";
var _minAnswers = 3;
var _nodes = [  "0xE3a98D9FAAB4a4B338B40A6dF6273Ab520152b8c",  "0xE3a98D9FAAB4a4B338B40A6dF6273Ab520152b8c",  "0xE3a98D9FAAB4a4B338B40A6dF6273Ab520152b8c","0xE3a98D9FAAB4a4B338B40A6dF6273Ab520152b8c","0xE3a98D9FAAB4a4B338B40A6dF6273Ab520152b8c","0xE3a98D9FAAB4a4B338B40A6dF6273Ab520152b8c"];
module.exports = function(deployer) {
  deployer.deploy(MTTPriceAggregator_Contract, _linkToken, _tokenDaiLp, _twapInterval, _storageT, _pairsStorage, _linkPriceFeed, _minAnswers,_nodes);
};



// const BigNumber = require('bignumber.js');
// const MTTTradingCallbacks_Contract = artifacts.require("MMTTradingCallbacks");
// module.exports = function(deployer) {
//   deployer.deploy(MTTTradingCallbacks_Contract);
// };

