// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IPool } from "aave/interfaces/IPool.sol";
import { DataTypes } from "aave/protocol/libraries/types/DataTypes.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { AaveHyperdriveCoreDeployer } from "../../../contracts/src/deployers/aave/AaveHyperdriveCoreDeployer.sol";
import { AaveHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/aave/AaveHyperdriveDeployerCoordinator.sol";
import { AaveTarget0Deployer } from "../../../contracts/src/deployers/aave/AaveTarget0Deployer.sol";
import { AaveTarget1Deployer } from "../../../contracts/src/deployers/aave/AaveTarget1Deployer.sol";
import { AaveTarget2Deployer } from "../../../contracts/src/deployers/aave/AaveTarget2Deployer.sol";
import { AaveTarget3Deployer } from "../../../contracts/src/deployers/aave/AaveTarget3Deployer.sol";
import { AaveTarget4Deployer } from "../../../contracts/src/deployers/aave/AaveTarget4Deployer.sol";
import { IAToken } from "../../../contracts/src/interfaces/IAToken.sol";
import { IAaveHyperdrive } from "../../../contracts/src/interfaces/IAaveHyperdrive.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract AaveHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    // The mainnet Aave V3 pool.
    IPool internal constant POOL =
        IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // The WETH token.
    IERC20 internal constant WETH =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // The aWETH AToken.
    IAToken internal constant AWETH =
        IAToken(0x4d5F47FA6A74757f35C14fD3a6Ef8E3C9BC514E8);

    // Whale accounts.
    address internal WETH_WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
    address internal AWETH_WHALE = 0x4353e2df4E3444e97e20b2bdA165BDd9A23913Ab;
    address[] internal baseTokenWhaleAccounts = [WETH_WHALE];
    address[] internal vaultSharesTokenWhaleAccounts = [AWETH_WHALE];

    /// @dev Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "AaveHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: baseTokenWhaleAccounts,
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: WETH,
                vaultSharesToken: IERC20(address(AWETH)),
                shareTolerance: 1e3,
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
                enableBaseWithdraws: true,
                enableShareWithdraws: true,
                baseWithdrawError: new bytes(0),
                isRebasing: true,
                shouldAccrueInterest: true,
                // The base test tolerances.
                closeLongWithBaseTolerance: 20,
                roundTripLpInstantaneousWithBaseTolerance: 1e5,
                roundTripLpWithdrawalSharesWithBaseTolerance: 1e5,
                roundTripLongInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithBaseTolerance: 1e5,
                roundTripLongMaturityWithBaseUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithBaseTolerance: 1e5,
                roundTripShortInstantaneousWithBaseUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithBaseTolerance: 1e5,
                roundTripShortMaturityWithBaseTolerance: 1e5,
                // The share test tolerances.
                closeLongWithSharesTolerance: 20,
                closeShortWithSharesTolerance: 100,
                roundTripLpInstantaneousWithSharesTolerance: 1e5,
                roundTripLpWithdrawalSharesWithSharesTolerance: 1e3,
                roundTripLongInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripLongInstantaneousWithSharesTolerance: 1e5,
                roundTripLongMaturityWithSharesUpperBoundTolerance: 1e3,
                roundTripLongMaturityWithSharesTolerance: 1e5,
                roundTripShortInstantaneousWithSharesUpperBoundTolerance: 1e3,
                roundTripShortInstantaneousWithSharesTolerance: 1e5,
                roundTripShortMaturityWithSharesTolerance: 1e5,
                // The verification tolerances.
                verifyDepositTolerance: 2,
                verifyWithdrawalTolerance: 2
            })
        )
    {}

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(20_276_503) {
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
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            baseAmount.mulDivDown(
                1e27,
                POOL.getReserveNormalizedIncome(address(WETH))
            );
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return
            shareAmount.mulDivDown(
                POOL.getReserveNormalizedIncome(address(WETH)),
                1e27
            );
    }

    /// @dev Deploys the Aave deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new AaveHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new AaveHyperdriveCoreDeployer()),
                    address(new AaveTarget0Deployer()),
                    address(new AaveTarget1Deployer()),
                    address(new AaveTarget2Deployer()),
                    address(new AaveTarget3Deployer()),
                    address(new AaveTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    function getSupply() internal view override returns (uint256, uint256) {
        return (AWETH.totalSupply(), AWETH.scaledTotalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (
            WETH.balanceOf(account),
            convertToShares(AWETH.balanceOf(account))
        );
    }

    /// Getters ///

    function test_getters() external view {
        assertEq(
            address(IAaveHyperdrive(address(hyperdrive)).vault()),
            address(POOL)
        );
        assertEq(
            hyperdrive.totalShares(),
            AWETH.balanceOf(address(hyperdrive))
        );
    }

    /// Price Per Share ///

    function test__pricePerVaultShare(uint256 sharesPaid) external {
        // Ensure that the share price is the expected value.
        uint256 totalSupply = AWETH.totalSupply();
        uint256 scaledTotalSupply = AWETH.scaledTotalSupply();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalSupply.divDown(scaledTotalSupply));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of shares. This will
        // be an approximation.
        sharesPaid = sharesPaid.normalizeToRange(
            2 *
                convertToShares(
                    hyperdrive.getPoolConfig().minimumTransactionAmount
                ),
            convertToShares(HyperdriveUtils.calculateMaxLong(hyperdrive))
        );
        uint256 hyperdriveSharesBefore = convertToShares(
            AWETH.balanceOf(address(hyperdrive))
        );
        openLong(bob, sharesPaid, false);
        assertApproxEqAbs(
            AWETH.balanceOf(address(hyperdrive)),
            (hyperdriveSharesBefore + sharesPaid).mulDown(vaultSharePrice),
            1e4
        );
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) internal override {
        // Get the normalized income prior to updating the time.
        uint256 reserveNormalizedIncome = POOL.getReserveNormalizedIncome(
            address(WETH)
        );

        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in the Aave pool. Since the vault share price is
        // given by `getReserveNormalizedIncome()`, we can simulate the accrual
        // of interest by multiplying the reserve normalized income by the
        // variable rate plus one. We also need to increase the
        // `lastUpdatedTimestamp` to avoid accruing interest when deposits or
        // withdrawals are processed.
        uint256 normalizedTime = timeDelta.divDown(365 days);
        reserveNormalizedIncome = variableRate >= 0
            ? reserveNormalizedIncome +
                reserveNormalizedIncome.mulDown(uint256(variableRate)).mulDown(
                    normalizedTime
                )
            : reserveNormalizedIncome -
                reserveNormalizedIncome.mulDown(uint256(-variableRate)).mulDown(
                    normalizedTime
                );
        bytes32 reserveDataLocation = keccak256(abi.encode(address(WETH), 52));
        DataTypes.ReserveDataLegacy memory data = POOL.getReserveData(
            address(WETH)
        );
        vm.store(
            address(POOL),
            bytes32(uint256(reserveDataLocation) + 1),
            bytes32(
                (uint256(data.currentLiquidityRate) << 128) |
                    uint256(reserveNormalizedIncome)
            )
        );
        vm.store(
            address(POOL),
            bytes32(uint256(reserveDataLocation) + 3),
            bytes32(
                (uint256(data.id) << 168) |
                    (block.timestamp << 128) |
                    data.currentStableBorrowRate
            )
        );
    }
}
