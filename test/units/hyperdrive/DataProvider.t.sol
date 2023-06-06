pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { Errors } from "contracts/src/libraries/Errors.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveStorage } from "contracts/src/HyperdriveStorage.sol";
import { HyperdriveTest, HyperdriveUtils } from "../../utils/HyperdriveTest.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdrive, MockHyperdriveDataProvider } from "../../mocks/MockHyperdrive.sol";
import { Lib } from "../../utils/Lib.sol";

contract HyperdriveDataProviderTest is HyperdriveTest {
    address constant GOVERNANCE = address(0x9090906);

    function setUp() public virtual override {
        vm.startPrank(alice);

        // Instantiate the base token.
        baseToken = new ERC20Mintable();
        IHyperdrive.Fees memory fees = IHyperdrive.Fees({
            curve: 478374743,
            flat: 32858328,
            governance: 318191919
        });
        // Instantiate Hyperdrive.
        uint256 apr = 0.05e18;
        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({
            baseToken: baseToken,
            initialSharePrice: INITIAL_SHARE_PRICE,
            positionDuration: POSITION_DURATION,
            checkpointDuration: CHECKPOINT_DURATION,
            timeStretch: HyperdriveUtils.calculateTimeStretch(apr),
            governance: GOVERNANCE,
            feeCollector: address(0x9090909),
            fees: fees,
            oracleSize: ORACLE_SIZE,
            updateGap: UPDATE_GAP
        });
        address dataProvider = address(new MockHyperdriveDataProvider(config));
        hyperdrive = IHyperdrive(
            address(new MockHyperdrive(config, dataProvider))
        );
        vm.stopPrank();
        vm.startPrank(GOVERNANCE);
        hyperdrive.setPauser(pauser, true);

        // Advance time so that Hyperdrive can look back more than a position
        // duration.
        vm.warp(POSITION_DURATION * 3);
    }

    function testLoadSlots() public {
        uint256[] memory slots = new uint256[](2);

        slots[0] = 16;
        slots[1] = 20;

        bytes32[] memory values = hyperdrive.load(slots);

        // Dumb address conversion to bytes, but this is the governance address we've fed in as bytes
        assertEq(
            values[0],
            bytes32(
                0x0000000000000000000000000000000000000000000000000000000009090906
            )
        );
    }
}
