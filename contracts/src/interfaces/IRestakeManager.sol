// SPDX-License-Identifier: Apache-2.0
import { IERC20 } from "./IERC20.sol";

interface IRestakeManager {
    /**
     * @notice  Deposits an ERC20 collateral token into the protocol
     * @dev     Convenience function to deposit without a referral ID and backwards compatibility
     * @param   _collateralToken  The address of the collateral ERC20 token to deposit
     * @param   _amount The amount of the collateral token to deposit in base units
     */
    function deposit(IERC20 _collateralToken, uint256 _amount) external;

    /**
     * @notice  Deposits an ERC20 collateral token into the protocol
     * @dev
     * The msg.sender must pre-approve this contract to move the tokens into the protocol
     * To deposit, the contract will:
     *   - Figure out which operator delegator to use
     *   - Transfer the collateral token to the operator delegator and deposit it into EigenLayer
     *   - Calculate and mint the appropriate amount of ezETH back to the user
     * ezETH will get inflated proportional to the value they are depositing vs the value already in the protocol
     * The collateral token specified must be pre-configured to be allowed in the protocol
     * @param   _collateralToken  The address of the collateral ERC20 token to deposit
     * @param   _amount The amount of the collateral token to deposit in base units
     * @param   _referralId The referral ID to use for the deposit (can be 0 if none)
     */
    function deposit(
        IERC20 _collateralToken,
        uint256 _amount,
        uint256 _referralId
    ) external;

    /**
     * @notice  Allows a user to deposit ETH into the protocol and get back ezETH
     * @dev     Convenience function to deposit without a referral ID and backwards compatibility
     */
    function depositETH() external payable;

    /**
     * @notice  Allows a user to deposit ETH into the protocol and get back ezETH
     * @dev     The amount of ETH sent into this function will be sent to the deposit queue to be
     * staked later by a validator.  Once staked it will be deposited into EigenLayer.
     * * @param   _referralId  The referral ID to use for the deposit (can be 0 if none)
     */
    function depositETH(uint256 _referralId) external payable;
}
