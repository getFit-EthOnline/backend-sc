// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FanToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals()))); // Initial mint to the contract deployer (could be a treasury or the admin wallet)
    }

     // Overriding the decimals function to set it to 0
    function decimals() public view virtual override returns (uint8) {
        return 0;
    }
}

