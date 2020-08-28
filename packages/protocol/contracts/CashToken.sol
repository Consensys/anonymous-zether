// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CashToken is ERC20 {
    constructor () ERC20("Anonymous Zether", "ZTH") {
        // etc
    }

    function mint(address account, uint256 amount) external { // just for testing---expose the method.
        _mint(account, amount);
    }
}
