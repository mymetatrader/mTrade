// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {UpgradableProxy} from "./UpgradableProxy.sol";

contract ChildChainManagerProxy is UpgradableProxy {
    constructor(address _proxyTo)
        UpgradableProxy(_proxyTo)
    {}
}
