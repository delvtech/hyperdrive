// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { StETHHyperdriveCoreDeployer } from "../../../contracts/src/deployers/steth/StETHHyperdriveCoreDeployer.sol";
import { StETHHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/steth/StETHHyperdriveDeployerCoordinator.sol";
import { StETHTarget0Deployer } from "../../../contracts/src/deployers/steth/StETHTarget0Deployer.sol";
import { StETHTarget1Deployer } from "../../../contracts/src/deployers/steth/StETHTarget1Deployer.sol";
import { StETHTarget2Deployer } from "../../../contracts/src/deployers/steth/StETHTarget2Deployer.sol";
import { StETHTarget3Deployer } from "../../../contracts/src/deployers/steth/StETHTarget3Deployer.sol";
import { StETHTarget4Deployer } from "../../../contracts/src/deployers/steth/StETHTarget4Deployer.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "../../../contracts/src/interfaces/ILido.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract StETHHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev The Lido storage location that tracks buffered ether reserves. We
    ///      can simulate the accrual of interest by updating this value.
    bytes32 internal constant BUFFERED_ETHER_POSITION =
        keccak256("lido.Lido.bufferedEther");

    /// @dev The stETH contract.
    ILido internal constant LIDO =
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    /// @dev Whale accounts.
    address internal STETH_WHALE = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address[] internal whaleAccounts = [STETH_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "StETHHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: new address[](0),
                vaultSharesTokenWhaleAccounts: whaleAccounts,
                baseToken: IERC20(ETH),
                vaultSharesToken: IERC20(LIDO),
                shareTolerance: 1e5,
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                enableBaseDeposits: true,
                enableShareDeposits: true,
                enableBaseWithdraws: false,
                enableShareWithdraws: true,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: true,
                shouldAccrueInterest: true,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                // NOTE: Base  withdrawals are disabled, so the tolerances are zero.
                //
                // The base test tolerances.
                closeLongWithBaseTolerance: 20,
                roundTripLpInstantaneousWithBaseTolerance: 0,
                roundTripLpWithdrawalSharesWithBaseTolerance: 0,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 0,
                roundTripLongInstantaneousWithBaseTolerance: 0,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 0,
                roundTripLongMaturityWithBaseTolerance: 0,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 0,
                roundTripShortInstantaneousWithBaseTolerance: 0,
                roundTripShortMaturityWithBaseTolerance: 0,
                // The share test tolerances.
                closeLongWithSharesTolerance: 20,
                closeShortWithSharesTolerance: 100,
                roundTripLpInstantaneousWithSharesTolerance: 1e5,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e5,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e4,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 100,
                roundTripLongMaturityWithSharesTolerance: 3e3,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e3,
                roundTripShortMaturityWithSharesTolerance: 1e3,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(17_376_154) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy Hyperdrive instances.
    /// @return The extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Converts base amount to the equivalent about in stETH.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        // Get protocol state information used for calculating shares.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        return baseAmount.mulDivDown(totalShares, totalPooledEther);
    }

    /// @dev Converts share amount to the equivalent amount in ETH.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        // Lido has a built-in function for computing price in terms of base.
        return LIDO.getPooledEthByShares(shareAmount);
    }

    /// @dev Deploys the rETH deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new StETHHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new StETHHyperdriveCoreDeployer()),
                    address(new StETHTarget0Deployer()),
                    address(new StETHTarget1Deployer()),
                    address(new StETHTarget2Deployer()),
                    address(new StETHTarget3Deployer()),
                    address(new StETHTarget4Deployer()),
                    LIDO
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (LIDO.getTotalPooledEther(), LIDO.getTotalShares());
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (account.balance, LIDO.sharesOf(account));
    }

    /// Getters ///

    /// @dev Test the instances getters.
    function test_getters() external view {
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
    }

    /// Price Per Share ///

    /// @dev Fuzz test that verifies that the vault share price is the price
    ///      that dictates the conversion between base and shares.
    /// @param basePaid the fuzz parameter for the base paid.
    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalPooledEther.divDown(totalShares));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH. This will
        // be an approximation since Lido uses `mulDivDown` whereas this test
        // pre-computes the share price.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            HyperdriveUtils.calculateMaxLong(hyperdrive)
        );
        uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));
        openLong(bob, basePaid);
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
            1e4
        );
    }

    /// Helpers ///

    /// @dev Advance time and accrue interest.
    /// @param timeDelta The time to advance.
    /// @param variableRate The variable rate.
    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in Lido. Since the share price is given by
        // `getTotalPooledEther() / getTotalShares()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        (, int256 interest) = LIDO.getTotalPooledEther().calculateInterest(
            variableRate,
            timeDelta
        );
        uint256 bufferedEther = interest >= 0
            ? LIDO.getBufferedEther() + uint256(interest)
            : LIDO.getBufferedEther() - uint256(-interest);
        vm.store(
            address(LIDO),
            BUFFERED_ETHER_POSITION,
            bytes32(bufferedEther)
        );
    }
}
