// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.7.6;

contract OtherContract {
    constructor(string memory test1, string memory test2) {
        test1 = test2;
    }
}

{
  "metadata": {
    "useLiteralContent": true
  },
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  }
}