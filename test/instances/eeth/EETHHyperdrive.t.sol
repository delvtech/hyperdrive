// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { ILiquidityPool } from "../../../contracts/src/interfaces/ILiquidityPool.sol";
import { IEETH } from "../../../contracts/src/interfaces/IEETH.sol";
import { EETHHyperdriveCoreDeployer } from "../../../contracts/src/deployers/eeth/EETHHyperdriveCoreDeployer.sol";
import { EETHHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/eeth/EETHHyperdriveDeployerCoordinator.sol";
import { EETHTarget0Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget0Deployer.sol";
import { EETHTarget1Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget1Deployer.sol";
import { EETHTarget2Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget2Deployer.sol";
import { EETHTarget3Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget3Deployer.sol";
import { EETHTarget4Deployer } from "../../../contracts/src/deployers/eeth/EETHTarget4Deployer.sol";
import { EETHConversions } from "../../../contracts/src/instances/eeth/EETHConversions.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IEETHHyperdrive } from "../../../contracts/src/interfaces/IEETHHyperdrive.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract EETHHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    /// @dev The mainnet liquidity pool.
    ILiquidityPool internal constant POOL =
        ILiquidityPool(0x308861A430be4cce5502d0A12724771Fc6DaF216);

    /// @dev The mainnet EETH token.
    IEETH internal constant EETH =
        IEETH(0x35fA164735182de50811E8e2E824cFb9B6118ac2);

    /// @dev The mainnet address that has the ability to call the rebase function.
    address internal constant MEMBERSHIP_MANAGER =
        0x3d320286E014C3e1ce99Af6d6B00f0C1D63E3000;

    /// @dev Whale accounts.
    address internal EETH_TOKEN_WHALE =
        0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address[] internal EETHTokenWhaleAccounts = [EETH_TOKEN_WHALE];

    /// @notice Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "EETHHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: new address[](0),
                vaultSharesTokenWhaleAccounts: EETHTokenWhaleAccounts,
                baseToken: IERC20(ETH),
                vaultSharesToken: IERC20(address(EETH)),
                shareTolerance: 1e5,
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                enableBaseDeposits: true,
                enableShareDeposits: true,
                enableBaseWithdraws: false,
                enableShareWithdraws: true,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: true,
                shouldAccrueInterest: true,
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
                roundTripLongInstantaneousWithSharesTolerance: 1e5,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithSharesTolerance: 1e5,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e5,
                roundTripShortMaturityWithSharesTolerance: 1e4,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            })
        )
    {}

    /// @notice Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_362_343) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy Hyperdrive instances.
    /// @return The extra data.
    function getExtraData() internal pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Converts base amount to the equivalent about in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            EETHConversions.convertToShares(
                POOL,
                IERC20(address(EETH)),
                baseAmount
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    /// @param shareAmount The share amount.
    /// @return The converted base amount.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            EETHConversions.convertToBase(
                POOL,
                IERC20(address(EETH)),
                shareAmount
            );
    }

    /// @dev Deploys the EETH deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new EETHHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new EETHHyperdriveCoreDeployer(POOL)),
                    address(new EETHTarget0Deployer(POOL)),
                    address(new EETHTarget1Deployer(POOL)),
                    address(new EETHTarget2Deployer(POOL)),
                    address(new EETHTarget3Deployer(POOL)),
                    address(new EETHTarget4Deployer(POOL)),
                    POOL
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (address(POOL).balance, EETH.totalShares());
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (account.balance, EETH.shares(account));
    }

    /// Getters ///

    /// @dev Test the instances getters.
    function test_getters() external view {
        assertEq(
            IEETHHyperdrive(address(hyperdrive)).liquidityPool(),
            address(POOL)
        );
    }

    /// Price Per Share ///

    /// @dev Fuzz test that verifies that the vault share price is the price
    ///      that dictates the conversion between base and shares.
    /// @param basePaid The fuzz parameter for the base paid.
    function test__pricePerVaultShare(uint256 basePaid) external {
        // Ensure that the share price is the expected value.
        (, uint256 totalSupplyShares) = getSupply();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(
            vaultSharePrice,
            POOL.getTotalPooledEther().divDown(totalSupplyShares)
        );

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of shares. This will
        // be an approximation.
        basePaid = basePaid.normalizeToRange(
            2 * hyperdrive.getPoolConfig().minimumTransactionAmount,
            hyperdrive.calculateMaxLong()
        );
        (, uint256 hyperdriveSharesBefore) = getTokenBalances(
            address(hyperdrive)
        );
        openLong(bob, basePaid);
        (, uint256 hyperdriveSharesAfter) = getTokenBalances(
            address(hyperdrive)
        );
        assertApproxEqAbs(
            hyperdriveSharesAfter,
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
            config.shareTolerance
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

        // Accrue interest in Etherfi. Since the share price is given by
        // `getTotalPooledEther() / getTotalShares()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        (, int256 etherToAdd) = POOL.getTotalPooledEther().calculateInterest(
            variableRate,
            timeDelta
        );
        vm.startPrank(MEMBERSHIP_MANAGER);
        POOL.rebase(int128(int256(etherToAdd)));
        vm.deal(address(POOL), uint256(etherToAdd));
    }
}
