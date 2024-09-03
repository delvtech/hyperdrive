// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { stdStorage, StdStorage } from "forge-std/Test.sol";
import { ChainlinkHyperdriveCoreDeployer } from "../../../contracts/src/deployers/chainlink/ChainlinkHyperdriveCoreDeployer.sol";
import { ChainlinkHyperdriveDeployerCoordinator } from "../../../contracts/src/deployers/chainlink/ChainlinkHyperdriveDeployerCoordinator.sol";
import { ChainlinkTarget0Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget0Deployer.sol";
import { ChainlinkTarget1Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget1Deployer.sol";
import { ChainlinkTarget2Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget2Deployer.sol";
import { ChainlinkTarget3Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget3Deployer.sol";
import { ChainlinkTarget4Deployer } from "../../../contracts/src/deployers/chainlink/ChainlinkTarget4Deployer.sol";
import { HyperdriveFactory } from "../../../contracts/src/factory/HyperdriveFactory.sol";
import { ChainlinkConversions } from "../../../contracts/src/instances/chainlink/ChainlinkConversions.sol";
import { IChainlinkAggregatorV3 } from "../../../contracts/src/interfaces/IChainlinkAggregatorV3.sol";
import { IChainlinkHyperdrive } from "../../../contracts/src/interfaces/IChainlinkHyperdrive.sol";
import { IERC20 } from "../../../contracts/src/interfaces/IERC20.sol";
import { IHyperdrive } from "../../../contracts/src/interfaces/IHyperdrive.sol";
import { IMorphoBlueHyperdrive } from "../../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { AssetId } from "../../../contracts/src/libraries/AssetId.sol";
import { ETH } from "../../../contracts/src/libraries/Constants.sol";
import { FixedPointMath, ONE } from "../../../contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "../../../contracts/src/libraries/HyperdriveMath.sol";
import { ERC20ForwarderFactory } from "../../../contracts/src/token/ERC20ForwarderFactory.sol";
import { ERC20Mintable } from "../../../contracts/test/ERC20Mintable.sol";
import { InstanceTest } from "../../utils/InstanceTest.sol";
import { HyperdriveUtils } from "../../utils/HyperdriveUtils.sol";
import { Lib } from "../../utils/Lib.sol";

contract ChainlinkHyperdriveTest is InstanceTest {
    using FixedPointMath for uint256;
    using HyperdriveUtils for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;
    using stdStorage for StdStorage;

    /// @dev Chainlink's proxy for the wstETH-ETH reference rate on Gnosis Chain.
    IChainlinkAggregatorV3 internal constant CHAINLINK_AGGREGATOR_PROXY =
        IChainlinkAggregatorV3(0x0064AC007fF665CF8D0D3Af5E0AD1c26a3f853eA);

    /// @dev The underlying aggregator used Chainlink's by Chainlink's proxy on
    ///      Gnosis chain.
    address internal constant CHAINLINK_AGGREGATOR =
        address(0x6dcF8CE1982Fc71E7128407c7c6Ce4B0C1722F55);

    /// @dev The address of the wstETH token on Gnosis Chain.
    IERC20 internal constant WSTETH =
        IERC20(0x6C76971f98945AE98dD7d4DFcA8711ebea946eA6);

    /// @dev The wstETH Whale accounts.
    address internal constant WSTETH_WHALE =
        address(0x458cD345B4C05e8DF39d0A07220feb4Ec19F5e6f);
    address[] internal vaultSharesTokenWhaleAccounts = [WSTETH_WHALE];

    /// @notice Instantiates the Instance testing suite with the configuration.
    constructor()
        InstanceTest(
            InstanceTestConfig({
                name: "Hyperdrive",
                kind: "ChainlinkHyperdrive",
                decimals: 18,
                baseTokenWhaleAccounts: new address[](0),
                vaultSharesTokenWhaleAccounts: vaultSharesTokenWhaleAccounts,
                baseToken: IERC20(address(0)),
                vaultSharesToken: WSTETH,
                shareTolerance: 0,
                minimumShareReserves: 1e15,
                minimumTransactionAmount: 1e15,
                positionDuration: POSITION_DURATION,
                fees: IHyperdrive.Fees({
                    curve: 0,
                    flat: 0,
                    governanceLP: 0,
                    governanceZombie: 0
                }),
                enableBaseDeposits: false,
                enableShareDeposits: true,
                enableBaseWithdraws: false,
                enableShareWithdraws: true,
                baseWithdrawError: abi.encodeWithSelector(
                    IHyperdrive.UnsupportedToken.selector
                ),
                isRebasing: false,
                // NOTE: Base deposits and withdrawals are disabled, so the
                // tolerances are zero.
                //
                // The base test tolerances.
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
    function setUp() public override __gnosis_chain_fork(35336446) {
        // Invoke the Instance testing suite setup.
        super.setUp();
    }

    /// Overrides ///

    /// @dev Gets the extra data used to deploy the Chainlink instance.
    /// @return The extra data containing the Chainlink aggregator and the
    ///         decimals that the instance should use.
    function getExtraData() internal pure override returns (bytes memory) {
        return abi.encode(CHAINLINK_AGGREGATOR_PROXY, uint8(18));
    }

    /// @dev Converts base amount to the equivalent about in shares.
    /// @param baseAmount The base amount.
    /// @return The converted share amount.
    function convertToShares(
        uint256 baseAmount
    ) internal view override returns (uint256) {
        return
            ChainlinkConversions.convertToShares(
                CHAINLINK_AGGREGATOR_PROXY,
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
            ChainlinkConversions.convertToBase(
                CHAINLINK_AGGREGATOR_PROXY,
                shareAmount
            );
    }

    /// @dev Deploys the Chainlink deployer coordinator contract.
    /// @param _factory The address of the Hyperdrive factory.
    /// @return The coordinator address.
    function deployCoordinator(
        address _factory
    ) internal override returns (address) {
        vm.startPrank(alice);
        return
            address(
                new ChainlinkHyperdriveDeployerCoordinator(
                    string.concat(config.name, "DeployerCoordinator"),
                    _factory,
                    address(new ChainlinkHyperdriveCoreDeployer()),
                    address(new ChainlinkTarget0Deployer()),
                    address(new ChainlinkTarget1Deployer()),
                    address(new ChainlinkTarget2Deployer()),
                    address(new ChainlinkTarget3Deployer()),
                    address(new ChainlinkTarget4Deployer())
                )
            );
    }

    /// @dev Fetches the total supply of the base and share tokens.
    /// @return The total supply of base.
    /// @return The total supply of vault shares.
    function getSupply() internal view override returns (uint256, uint256) {
        return (0, WSTETH.totalSupply());
    }

    /// @dev Fetches the token balance information of an account.
    /// @param account The account to query.
    /// @return The balance of base.
    /// @return The balance of vault shares.
    function getTokenBalances(
        address account
    ) internal view override returns (uint256, uint256) {
        return (0, WSTETH.balanceOf(account));
    }

    /// Getters ///

    /// @dev Test the instances getters.
    function test_getters() external view {
        assertEq(
            address(IChainlinkHyperdrive(address(hyperdrive)).aggregator()),
            address(CHAINLINK_AGGREGATOR_PROXY)
        );
        (, uint256 totalShares) = getTokenBalances(address(hyperdrive));
        assertEq(hyperdrive.totalShares(), totalShares);
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

        // Get the latest round ID and answer. We'll overwrite this round ID
        // with the updated answer.
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = CHAINLINK_AGGREGATOR_PROXY.latestRoundData();
        uint256 answer_ = uint256(answer);

        // Accrue interest in the Chainlink wstETH market. We do this by
        // overwriting the latest round's answer.
        (answer_, ) = uint256(answer_).calculateInterest(
            variableRate,
            timeDelta
        );
        bytes32 latestRoundLocation = keccak256(
            abi.encode(uint32(roundId), 44)
        );
        vm.store(
            CHAINLINK_AGGREGATOR,
            latestRoundLocation,
            bytes32((updatedAt << 192) | answer_)
        );
    }
}
