// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;
import "@yield-protocol/utils-v2/src/token/ERC20Permit.sol";

/**
 * @title CKESMock
 * @notice Mock token for cKES (Celo Kenyan Shilling)
 */
contract CKESMock is ERC20Permit {
    constructor() ERC20Permit("Celo Kenyan Shilling", "cKES", 18) { }

    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
