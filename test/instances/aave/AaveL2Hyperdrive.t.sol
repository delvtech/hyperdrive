// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { IL2Pool } from "contracts/src/interfaces/IAave.sol";
import { DataTypes } from "aave/protocol/libraries/types/DataTypes.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { IAaveL2Hyperdrive } from "contracts/src/interfaces/IAaveL2Hyperdrive.sol";
import { AaveL2Conversions } from "contracts/src/instances/aave-l2/AaveL2Conversions.sol";
import { AaveL2HyperdriveCoreDeployer } from "contracts/src/deployers/aave-l2/AaveL2HyperdriveCoreDeployer.sol";
import { AaveL2HyperdriveDeployerCoordinator } from "contracts/src/deployers/aave-l2/AaveL2HyperdriveDeployerCoordinator.sol";
import { AaveL2Target0Deployer } from "contracts/src/deployers/aave-l2/AaveL2Target0Deployer.sol";
import { AaveL2Target1Deployer } from "contracts/src/deployers/aave-l2/AaveL2Target1Deployer.sol";
import { AaveL2Target2Deployer } from "contracts/src/deployers/aave-l2/AaveL2Target2Deployer.sol";
import { AaveL2Target3Deployer } from "contracts/src/deployers/aave-l2/AaveL2Target3Deployer.sol";
import { AaveL2Target4Deployer } from "contracts/src/deployers/aave-l2/AaveL2Target4Deployer.sol";
import { IAToken } from "contracts/src/interfaces/IAToken.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { InstanceTest } from "test/utils/InstanceTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract AaveL2HyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    // The Arbitrum AaveL2 V3 pool.
    IL2Pool internal constant POOL =
        IL2Pool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    // The WETH token.
    IERC20 internal constant WETH =
        IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // The aWETH AToken.
    IAToken internal constant AWETH =
        IAToken(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8);

    // Whale accounts.
    address internal WETH_WHALE = 0x70d95587d40A2caf56bd97485aB3Eec10Bee6336;
    address internal AWETH_WHALE_1 = 0x6286b9f080D27f860F6b4bb0226F8EF06CC9F2Fc;
    address internal AWETH_WHALE_2 = 0xB7Fb2B774Eb5E2DaD9C060fb367AcBdc7fA7099B;
    address internal AWETH_WHALE_3 = 0x8AeCc5526F92A46718f8E68516D22038D8670E0D;
    address internal AWETH_WHALE_4 = 0x1de5366615BCEB1BDb7274536Bf3fc9f06Aa9c2C;

    address[] internal baseTokenWhaleAccounts = [WETH_WHALE];
    address[] internal vaultSharesTokenWhaleAccounts = [
        AWETH_WHALE_1,
        AWETH_WHALE_2,
        AWETH_WHALE_3,
        AWETH_WHALE_4
    ];

    /// @dev Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "AaveL2Hyperdrive",
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
    function setUp() public override __arbitrum_fork(248_038_178) {
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
        return AaveL2Conversions.convertToShares(WETH, POOL, baseAmount);
    }

    /// @dev Converts share amount to the equivalent amount in base.
    function convertToBase(
        uint256 shareAmount
    ) internal view override returns (uint256) {
        return AaveL2Conversions.convertToBase(WETH, POOL, shareAmount);
    }

    /// @dev Deploys the AaveL2 deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new AaveL2HyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new AaveL2HyperdriveCoreDeployer()),
                    address(new AaveL2Target0Deployer()),
                    address(new AaveL2Target1Deployer()),
                    address(new AaveL2Target2Deployer()),
                    address(new AaveL2Target3Deployer()),
                    address(new AaveL2Target4Deployer())
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
            address(IAaveL2Hyperdrive(address(hyperdrive)).vault()),
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
        (uint256 totalAmount, ) = HyperdriveUtils.calculateInterest(
            reserveNormalizedIncome,
            variableRate,
            timeDelta
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
                    uint256(totalAmount)
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
