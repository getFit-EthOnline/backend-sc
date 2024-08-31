// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract mUSDC is ERC20 {
    constructor() ERC20("mUSDC", "USD") {
        _mint(msg.sender, 1000000 * (10 ** uint256(decimals())));
    }

    // Overriding the decimals function to set it to 6
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
