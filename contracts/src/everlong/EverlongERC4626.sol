// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";

contract EverlongERC4626 is ERC4626 {
    /// @notice Whether virtual shares will be used to mitigate the inflation attack.
    bool public constant useVirtualShares = true;

    /// @notice Used to reduce the feasibility of an inflation attack.
    uint8 public constant decimalsOffset = 3;

    /// @notice Address of the underlying Hyperdrive instance.
    address internal immutable _underlying;

    /// @notice Decimals used by the underlying Hyperdrive asset.
    uint8 internal immutable _decimals;

    /// @notice Name of the Everlong token.
    string internal _name;

    /// @notice Symbol of the Everlong token.
    string internal _symbol;

    constructor(
        address underlying_,
        string memory name_,
        string memory symbol_
    ) {
        _underlying = IHyperdrive(underlying_).vaultSharesToken();

        (bool success, uint8 result) = _tryGetAssetDecimals(underlying_);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;

        _name = name_;
        _symbol = symbol_;
    }

    /// @dev Address of the underlying Hyperdrive instance's vaultSharesToken.
    ///
    /// - MUST be an ERC20 token contract.
    /// - MUST NOT revert.
    function asset() public view virtual override returns (address) {
        return _underlying;
    }

    /// @dev Returns the name of the Everlong token.
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /// @dev Returns the symbol of the Everlong token.
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /// @dev Returns whether virtual shares will be used to mitigate the inflation attack.
    /// See: https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
    ///
    /// - MUST NOT revert.
    function _useVirtualShares() internal view virtual override returns (bool) {
        return useVirtualShares;
    }

    /// @dev Returns the number of decimals of the underlying asset.
    ///
    /// - MUST NOT revert.
    function _underlyingDecimals()
        internal
        view
        virtual
        override
        returns (uint8)
    {
        return _decimals;
    }

    /// @dev A non-zero value used to make the inflation attack even more unfeasible.
    /// Only used when {_useVirtualShares} returns true.
    ///
    /// - MUST NOT revert.
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return decimalsOffset;
    }

    // TODO: Might not need this but including for convenience.
    function _beforeWithdraw(uint256, uint256) internal override {
        // revert("TODO");
    }

    // TODO: Might not need this but including for convenience.
    function _afterDeposit(uint256, uint256) internal override {
        // revert("TODO");
    }
}
