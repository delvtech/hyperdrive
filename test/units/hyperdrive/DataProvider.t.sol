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
