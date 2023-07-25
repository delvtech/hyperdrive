// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { console } from "forge-std/console.sol";
import { Script } from "forge-std/Script.sol";
import { ERC4626DataProvider } from "contracts/src/instances/ERC4626DataProvider.sol";
import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
import { IERC4626 } from "contracts/src/interfaces/IERC4626.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { Lib } from "test/utils/Lib.sol";

/// @author DELV
/// @title DevnetRepro
/// @notice This script reads from a remote Hyperdrive instance and generates a
///         test suite that recreates the instance's state in a MockHyperdrive
///         instance. This is useful for debugging and testing.
/// @custom:disclaimer The language used in this code is for coding convenience
///                    only, and is not intended to, and does not, have any
///                    particular legal or regulatory significance.
contract DevnetRepro is Script {
    using FixedPointMath for uint256;
    using HyperdriveUtils for IHyperdrive;
    using Lib for *;

    string internal REPRO_PATH =
        string.concat(vm.projectRoot(), "/test/Generated.t.sol");
    IHyperdrive internal HYPERDRIVE = IHyperdrive(vm.envAddress("HYPERDRIVE"));
    ERC20Mintable internal BASE = ERC20Mintable(vm.envAddress("BASE"));

    function setUp() external {}

    // prettier-ignore
    function run() external {
        // Query the Hyperdrive instance for some data.
        IERC4626 pool = ERC4626DataProvider(address(HYPERDRIVE)).pool();
        uint256 balance = pool.balanceOf(address(HYPERDRIVE));
        IHyperdrive.PoolConfig memory config = HYPERDRIVE.getPoolConfig();
        IHyperdrive.PoolInfo memory info = HYPERDRIVE.getPoolInfo();

        // Remove the existing repro file, if any.
        try vm.removeFile(REPRO_PATH) {} catch {}

        // The following takes the data gathered from the instance and writes
        // a unit test line-by-line that will set up a MockHyperdrive instance
        // with the same pool configuration and state as the remote instance.
        vm.writeLine(REPRO_PATH, "// SPDX-License-Identifier: Apache-2.0");
        vm.writeLine(REPRO_PATH, "pragma solidity 0.8.19;");
        vm.writeLine(REPRO_PATH, "");
        vm.writeLine(REPRO_PATH, "import { console } from \"forge-std/console.sol\";");
        vm.writeLine(REPRO_PATH, "import { IERC20 } from \"contracts/src/interfaces/IERC20.sol\";");
        vm.writeLine(REPRO_PATH, "import { IHyperdrive } from \"contracts/src/interfaces/IHyperdrive.sol\";");
        vm.writeLine(REPRO_PATH, "import { MockHyperdrive } from \"test/mocks/MockHyperdrive.sol\";");
        vm.writeLine(REPRO_PATH, "import { HyperdriveTest } from \"test/utils/HyperdriveTest.sol\";");
        vm.writeLine(REPRO_PATH, "import { HyperdriveUtils } from \"test/utils/HyperdriveUtils.sol\";");
        vm.writeLine(REPRO_PATH, "import { Lib } from \"test/utils/Lib.sol\";");
        vm.writeLine(REPRO_PATH, "");
        vm.writeLine(REPRO_PATH, "contract TestRepro is HyperdriveTest {");
        vm.writeLine(REPRO_PATH, "    using HyperdriveUtils for *;");
        vm.writeLine(REPRO_PATH, "    using Lib for *;");
        vm.writeLine(REPRO_PATH, "");
        vm.writeLine(REPRO_PATH, "    function setUp() public override {");
        vm.writeLine(REPRO_PATH, "        super.setUp();");
        vm.writeLine(REPRO_PATH, "");
        vm.writeLine(REPRO_PATH, "        // Recreate a Hyperdrive instance from a state dump.");
        vm.writeLine(REPRO_PATH, "        IHyperdrive.PoolConfig memory config = IHyperdrive.PoolConfig({");
        vm.writeLine(REPRO_PATH, "            baseToken: IERC20(address(baseToken)),");
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            initialSharePrice: ", vm.toString(config.initialSharePrice)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            minimumShareReserves: ", vm.toString(config.minimumShareReserves)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            positionDuration: ", vm.toString(config.positionDuration)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            checkpointDuration: ", vm.toString(config.checkpointDuration)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            timeStretch: ", vm.toString(config.timeStretch)), ","));
        vm.writeLine(REPRO_PATH, "            governance: alice,");
        vm.writeLine(REPRO_PATH, "            feeCollector: alice,");
        vm.writeLine(REPRO_PATH, "            fees: IHyperdrive.Fees({");
        vm.writeLine(REPRO_PATH, string.concat(string.concat("                curve: ", vm.toString(config.fees.curve)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("                flat: ", vm.toString(config.fees.curve)), ","));
        vm.writeLine(REPRO_PATH, string.concat("                governance: ", vm.toString(config.fees.curve)));
        vm.writeLine(REPRO_PATH, "            }),");
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            oracleSize: ", vm.toString(config.oracleSize)), ","));
        vm.writeLine(REPRO_PATH, string.concat("            updateGap: ", vm.toString(config.updateGap)));
        vm.writeLine(REPRO_PATH, "        });");
        vm.writeLine(REPRO_PATH, "        deploy(alice, config);");
        vm.writeLine(REPRO_PATH, "        IHyperdrive.MarketState memory state = IHyperdrive.MarketState({");
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            shareReserves: ", vm.toString(info.shareReserves)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            bondReserves: ", vm.toString(info.bondReserves)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            longsOutstanding: ", vm.toString(info.longsOutstanding)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            shortsOutstanding: ", vm.toString(info.shortsOutstanding)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            longAverageMaturityTime: ", vm.toString(info.longAverageMaturityTime)), ","));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("            shortAverageMaturityTime: ", vm.toString(info.shortAverageMaturityTime)), ","));
        vm.writeLine(REPRO_PATH, "            longOpenSharePrice: 0,");
        vm.writeLine(REPRO_PATH, "            shortBaseVolume: 0,");
        vm.writeLine(REPRO_PATH, "            isInitialized: true,");
        vm.writeLine(REPRO_PATH, "            isPaused: false");
        vm.writeLine(REPRO_PATH, "        });");
        vm.writeLine(REPRO_PATH, "        MockHyperdrive(address(hyperdrive)).setMarketState(state);");
        vm.writeLine(REPRO_PATH, string.concat(string.concat("        MockHyperdrive(address(hyperdrive)).setTotalShares(", vm.toString(balance.divDown(info.sharePrice))), ");"));
        vm.writeLine(REPRO_PATH, string.concat(string.concat("        baseToken.mint(address(hyperdrive), ", vm.toString(balance)), ");"));
        vm.writeLine(REPRO_PATH, "    }");
        vm.writeLine(REPRO_PATH, "}");

        console.log("Repro script written to %s. Move this to a new path to avoid being overwritten", REPRO_PATH);
    }
}
