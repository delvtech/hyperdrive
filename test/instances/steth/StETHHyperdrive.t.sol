// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { StETHHyperdriveCoreDeployer } from "contracts/src/deployers/steth/StETHHyperdriveCoreDeployer.sol";
import { StETHHyperdriveDeployerCoordinator } from "contracts/src/deployers/steth/StETHHyperdriveDeployerCoordinator.sol";
import { StETHTarget0Deployer } from "contracts/src/deployers/steth/StETHTarget0Deployer.sol";
import { StETHTarget1Deployer } from "contracts/src/deployers/steth/StETHTarget1Deployer.sol";
import { StETHTarget2Deployer } from "contracts/src/deployers/steth/StETHTarget2Deployer.sol";
import { StETHTarget3Deployer } from "contracts/src/deployers/steth/StETHTarget3Deployer.sol";
import { StETHTarget4Deployer } from "contracts/src/deployers/steth/StETHTarget4Deployer.sol";
import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ILido } from "contracts/src/interfaces/ILido.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { ETH } from "contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "test/utils/InstanceTest.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

contract StETHHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using Lib for *;
    using stdStorage for StdStorage;

    // The Lido storage location that tracks buffered ether reserves. We can
    // simulate the accrual of interest by updating this value.
    bytes32 internal constant BUFFERED_ETHER_POSITION =
        keccak256("lido.Lido.bufferedEther");

    ILido internal constant LIDO =
        ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    // Whale accounts.
    address internal STETH_WHALE = 0x1982b2F5814301d4e9a8b0201555376e62F82428;
    address[] internal whaleAccounts = [STETH_WHALE];

    /// @dev Instantiates the instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig(
                "Hyperdrive",
                "StETHHyperdrive",
                new address[](0),
                whaleAccounts,
                IERC20(ETH),
                IERC20(LIDO),
                1e5,
                1e15,
                POSITION_DURATION,
                true,
                true,
                false,
                true,
                abi.encodeWithSelector(IHyperdrive.UnsupportedToken.selector)
            )
        )
    {}

    /// @dev Forge function that is invoked to setup the testing environment.
    function setUp() public override __mainnet_fork(17_376_154) {
        // Invoke the instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy Hyperdrive instances.
    /// @return The extra data.
    function getExtraData() public pure override returns (bytes memory) {
        return new bytes(0);
    }

    /// @dev Converts base amount to the equivalent about in stETH.
    function convertToShares(
        uint256 baseAmount
    ) public view override returns (uint256) {
        // Get protocol state information used for calculating shares.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        return baseAmount.mulDivDown(totalShares, totalPooledEther);
    }

    /// @dev Converts share amount to the equivalent amount in ETH.
    function convertToBase(
        uint256 shareAmount
    ) public view override returns (uint256) {
        // Lido has a built-in function for computing price in terms of base.
        return LIDO.getPooledEthByShares(shareAmount);
    }

    /// @dev Deploys the rETH deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    function deployCoordinator(
        address _factory
    ) public override returns (address) {
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
    function getSupply() public view override returns (uint256, uint256) {
        return (LIDO.getTotalPooledEther(), LIDO.getTotalShares());
    }

    /// @dev Fetches the token balance information of an account.
    function getTokenBalances(
        address account
    ) public view override returns (uint256, uint256) {
        return (LIDO.balanceOf(account), LIDO.sharesOf(account));
    }

    /// @dev Verifies that deposit accounting is correct when opening positions.
    function verifyDeposit(
        address trader,
        uint256 amountPaid,
        bool asBase,
        uint256 totalBaseBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        if (asBase) {
            // Ensure that the amount of pooled ether increased by the base paid.
            assertEq(LIDO.getTotalPooledEther(), totalBaseBefore + amountPaid);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(bob.balance, traderBalancesBefore.ETHBalance - amountPaid);

            // Ensure that the stETH balances were updated correctly.
            assertApproxEqAbs(
                LIDO.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.baseBalance + amountPaid,
                1
            );
            assertEq(LIDO.balanceOf(trader), traderBalancesBefore.baseBalance);

            // Ensure that the stETH shares were updated correctly.
            uint256 expectedShares = amountPaid.mulDivDown(
                totalSharesBefore,
                totalBaseBefore
            );
            assertEq(LIDO.getTotalShares(), totalSharesBefore + expectedShares);
            assertEq(
                LIDO.sharesOf(address(hyperdrive)),
                hyperdriveBalancesBefore.sharesBalance + expectedShares
            );
            assertEq(LIDO.sharesOf(bob), traderBalancesBefore.sharesBalance);
        } else {
            // Ensure that the amount of pooled ether stays the same.
            assertEq(LIDO.getTotalPooledEther(), totalBaseBefore);

            // Ensure that the ETH balances were updated correctly.
            assertEq(
                address(hyperdrive).balance,
                hyperdriveBalancesBefore.ETHBalance
            );
            assertEq(trader.balance, traderBalancesBefore.ETHBalance);

            // Ensure that the stETH balances were updated correctly.
            assertApproxEqAbs(
                LIDO.balanceOf(address(hyperdrive)),
                hyperdriveBalancesBefore.baseBalance + amountPaid,
                1
            );
            assertApproxEqAbs(
                LIDO.balanceOf(trader),
                traderBalancesBefore.baseBalance - amountPaid,
                1
            );

            // Ensure that the stETH shares were updated correctly.
            uint256 expectedShares = amountPaid.mulDivDown(
                totalSharesBefore,
                totalBaseBefore
            );
            assertEq(LIDO.getTotalShares(), totalSharesBefore);
            assertApproxEqAbs(
                LIDO.sharesOf(address(hyperdrive)),
                hyperdriveBalancesBefore.sharesBalance + expectedShares,
                1
            );
            assertApproxEqAbs(
                LIDO.sharesOf(trader),
                traderBalancesBefore.sharesBalance - expectedShares,
                1
            );
        }
    }

    /// @dev Verifies that withdrawal accounting is correct when closing positions.
    function verifyWithdrawal(
        address trader,
        uint256 baseProceeds,
        bool asBase,
        uint256 totalPooledEtherBefore,
        uint256 totalSharesBefore,
        AccountBalances memory traderBalancesBefore,
        AccountBalances memory hyperdriveBalancesBefore
    ) internal view override {
        // Base withdraws are not supported for this instance.
        if (asBase) {
            revert IHyperdrive.UnsupportedToken();
        }

        // Ensure that the total pooled ether and shares stays the same.
        assertEq(LIDO.getTotalPooledEther(), totalPooledEtherBefore);
        assertApproxEqAbs(LIDO.getTotalShares(), totalSharesBefore, 1);

        // Ensure that the ETH balances were updated correctly.
        assertEq(
            address(hyperdrive).balance,
            hyperdriveBalancesBefore.ETHBalance
        );
        assertEq(trader.balance, traderBalancesBefore.ETHBalance);

        // Ensure that the stETH balances were updated correctly.
        assertApproxEqAbs(
            LIDO.balanceOf(address(hyperdrive)),
            hyperdriveBalancesBefore.baseBalance - baseProceeds,
            1
        );
        assertApproxEqAbs(
            LIDO.balanceOf(trader),
            traderBalancesBefore.baseBalance + baseProceeds,
            1
        );

        // Ensure that the stETH shares were updated correctly.
        uint256 expectedShares = baseProceeds.mulDivDown(
            totalSharesBefore,
            totalPooledEtherBefore
        );
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveBalancesBefore.sharesBalance - expectedShares,
            1
        );
        assertApproxEqAbs(
            LIDO.sharesOf(trader),
            traderBalancesBefore.sharesBalance + expectedShares,
            1
        );
    }

    /// Price Per Share ///

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

    /// Long ///

    function test_open_long_refunds() external {
        vm.startPrank(bob);

        // Ensure that Bob receives a refund on the excess ETH that he sent
        // when opening a long with "asBase" set to true.
        uint256 ethBalanceBefore = address(bob).balance;
        hyperdrive.openLong{ value: 2e18 }(
            1e18,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore - 1e18);

        // Ensure that Bob receives a  refund when he opens a long with "asBase"
        // set to false and sends ether to the contract.
        ethBalanceBefore = address(bob).balance;
        hyperdrive.openLong{ value: 0.5e18 }(
            1e18,
            0,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore);
    }

    /// Short ///

    function test_open_short_refunds() external {
        vm.startPrank(bob);

        // Ensure that Bob receives a refund on the excess ETH that he sent
        // when opening a short with "asBase" set to true.
        uint256 ethBalanceBefore = address(bob).balance;
        (, uint256 basePaid) = hyperdrive.openShort{ value: 2e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: true,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore - basePaid);

        // Ensure that Bob receives a refund when he opens a short with "asBase"
        // set to false and sends ether to the contract.
        ethBalanceBefore = address(bob).balance;
        hyperdrive.openShort{ value: 0.5e18 }(
            1e18,
            1e18,
            0,
            IHyperdrive.Options({
                destination: bob,
                asBase: false,
                extraData: new bytes(0)
            })
        );
        assertEq(address(bob).balance, ethBalanceBefore);
    }

    function test_round_trip_long() external {
        // Get some balance information before the deposit.
        LIDO.sharesOf(address(hyperdrive));

        // Bob opens a long by depositing ETH.
        uint256 basePaid = HyperdriveUtils.calculateMaxLong(hyperdrive);
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);

        // Get some balance information before the withdrawal.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );

        // Bob closes his long with stETH as the target asset.
        uint256 shareProceeds = closeLong(bob, maturityTime, longAmount, false);
        uint256 baseProceeds = shareProceeds.mulDivDown(
            LIDO.getTotalPooledEther(),
            LIDO.getTotalShares()
        );

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
    }

    function test__DOSStethHyperdriveCloseLong() external {
        //###########################################################################"
        //#### TEST: Denial of Service when LIDO's `TotalPooledEther` decreases. ####"
        //###########################################################################"

        // Ensure that the share price is the expected value.
        uint256 totalPooledEther = LIDO.getTotalPooledEther();
        uint256 totalShares = LIDO.getTotalShares();
        uint256 vaultSharePrice = hyperdrive.getPoolInfo().vaultSharePrice;
        assertEq(vaultSharePrice, totalPooledEther.divDown(totalShares));

        // Ensure that the share price accurately predicts the amount of shares
        // that will be minted for depositing a given amount of ETH. This will
        // be an approximation since Lido uses `mulDivDown` whereas this test
        // pre-computes the share price.
        uint256 basePaid = HyperdriveUtils.calculateMaxLong(hyperdrive) / 10;
        uint256 hyperdriveSharesBefore = LIDO.sharesOf(address(hyperdrive));

        // Bob calls openLong()
        (uint256 maturityTime, uint256 longAmount) = openLong(bob, basePaid);
        // Bob paid basePaid == ", basePaid);
        // Bob received longAmount == ", longAmount);
        assertApproxEqAbs(
            LIDO.sharesOf(address(hyperdrive)),
            hyperdriveSharesBefore + basePaid.divDown(vaultSharePrice),
            1e4
        );

        // Get some balance information before the withdrawal.
        uint256 totalPooledEtherBefore = LIDO.getTotalPooledEther();
        uint256 totalSharesBefore = LIDO.getTotalShares();
        AccountBalances memory bobBalancesBefore = getAccountBalances(bob);
        AccountBalances memory hyperdriveBalancesBefore = getAccountBalances(
            address(hyperdrive)
        );
        uint256 snapshotId = vm.snapshot();

        // Taking a Snapshot of the state
        // Bob closes his long with stETH as the target asset.
        uint256 shareProceeds = closeLong(
            bob,
            maturityTime,
            longAmount / 2,
            false
        );
        uint256 baseProceeds = shareProceeds.mulDivDown(
            LIDO.getTotalPooledEther(),
            LIDO.getTotalShares()
        );

        // Ensure that Lido's aggregates and the token balances were updated
        // correctly during the trade.
        verifyWithdrawal(
            bob,
            baseProceeds,
            false,
            totalPooledEtherBefore,
            totalSharesBefore,
            bobBalancesBefore,
            hyperdriveBalancesBefore
        );
        // # Reverting to the saved state Snapshot #\n");
        vm.revertTo(snapshotId);

        // # Manipulating Lido's totalPooledEther : removing only 1e18
        bytes32 balanceBefore = vm.load(
            address(LIDO),
            bytes32(
                0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
            )
        );
        // LIDO.CL_BALANCE_POSITION Before: ", uint(balanceBefore));
        uint(LIDO.getTotalPooledEther());
        hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime),
            bob
        );
        vm.store(
            address(LIDO),
            bytes32(
                uint256(
                    0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
                )
            ),
            bytes32(uint256(balanceBefore) - 1e18)
        );

        // Avoid Stack too deep
        uint256 maturityTime_ = maturityTime;
        uint256 longAmount_ = longAmount;

        vm.load(
            address(LIDO),
            bytes32(
                uint256(
                    0xa66d35f054e68143c18f32c990ed5cb972bb68a68f500cd2dd3a16bbf3686483
                )
            )
        );

        // Bob closes his long with stETH as the target asset.
        hyperdrive.balanceOf(
            AssetId.encodeAssetId(AssetId.AssetIdPrefix.Long, maturityTime_),
            bob
        );

        // The fact that this doesn't revert means that it works
        closeLong(bob, maturityTime_, longAmount_ / 2, false);
    }

    /// Helpers ///

    function advanceTime(
        uint256 timeDelta,
        int256 variableRate
    ) public override {
        // Advance the time.
        vm.warp(block.timestamp + timeDelta);

        // Accrue interest in Lido. Since the share price is given by
        // `getTotalPooledEther() / getTotalShares()`, we can simulate the
        // accrual of interest by multiplying the total pooled ether by the
        // variable rate plus one.
        uint256 bufferedEther = variableRate >= 0
            ? LIDO.getBufferedEther() +
                LIDO.getTotalPooledEther().mulDown(uint256(variableRate))
            : LIDO.getBufferedEther() -
                LIDO.getTotalPooledEther().mulDown(uint256(variableRate));
        vm.store(
            address(LIDO),
            BUFFERED_ETHER_POSITION,
            bytes32(bufferedEther)
        );
    }
}
