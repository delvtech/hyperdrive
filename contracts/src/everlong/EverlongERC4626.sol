// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC4626 } from "solady/tokens/ERC4626.sol";
import { VERSION, EVERLONG_KIND } from "../libraries/Constants.sol";

/// @author DELV
/// @title EverlongERC4626
/// @notice Everlong ERC4626 vault compatibility and functionality.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract EverlongERC4626 is ERC4626 {
    /// @notice Virtual shares are used to mitigate inflation attacks.
    bool public constant useVirtualShares = true;

    /// @notice Used to reduce the feasibility of an inflation attack.
    /// TODO: Determine the appropriate value for our case. Current value
    ///       was picked arbitrarily.
    uint8 public constant decimalsOffset = 3;

    /// @notice Address of the Hyperdrive instance wrapped by Everlong.
    address public immutable hyperdrive;

    /// @notice ERC20 token used for deposits, idle liquidity, and
    ///         the purchase of bonds from the Hyperdrive instance.
    ///         This is also the underlying Hyperdrive instance's
    ///         vaultSharesToken.
    address internal immutable _baseAsset;

    /// @notice Decimals used by the {_baseAsset}.
    uint8 internal immutable _decimals;

    /// @notice Name of the Everlong token.
    string internal _name;

    /// @notice Kind of the Everlong contract.
    string internal constant _kind = EVERLONG_KIND;

    /// @notice Symbol of the Everlong token.
    string internal _symbol;

    /// @notice Initializes parameters for Everlong's ERC4626 functionality.
    /// @param hyperdrive_ Address of the Hyperdrive instance wrapped by Everlong.
    /// @param name_ Name of the ERC20 token managed by Everlong.
    /// @param symbol_ Symbol of the ERC20 token managed by Everlong.
    constructor(
        address hyperdrive_,
        string memory name_,
        string memory symbol_
    ) {
        hyperdrive = hyperdrive_;
        _baseAsset = IHyperdrive(hyperdrive_).vaultSharesToken();
        _name = name_;
        _symbol = symbol_;

        // Attempt to retrieve the decimals from the {_baseAsset} contract.
        // If it does not implement `decimals() (uint256)`, use the default.
        (bool success, uint8 result) = _tryGetAssetDecimals(_baseAsset);
        _decimals = success ? result : _DEFAULT_UNDERLYING_DECIMALS;
    }

    /// @dev Address of the underlying Hyperdrive instance.
    /// @dev MUST be an ERC20 token contract.
    /// @dev MUST NOT revert.
    function asset() public view virtual override returns (address) {
        return _baseAsset;
    }

    /// @dev Returns the name of the Everlong token.
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /// @dev Returns the name of the Everlong contract.
    function kind() public view virtual returns (string memory) {
        return _kind;
    }

    /// @dev Returns the version of the Everlong contract.
    function version() public view virtual returns (string memory) {
        return VERSION;
    }

    /// @dev Returns the symbol of the Everlong token.
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /// @dev Returns whether virtual shares will be used to mitigate the inflation attack.
    /// @dev See: https://github.com/OpenZeppelin/openzeppelin-contracts/issues/3706
    /// @dev MUST NOT revert.
    function _useVirtualShares() internal view virtual override returns (bool) {
        return useVirtualShares;
    }

    /// @dev Returns the number of decimals of the underlying asset.
    /// @dev MUST NOT revert.
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
    /// @dev MUST NOT revert.
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
