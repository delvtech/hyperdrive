// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import { VmSafe } from "forge-std/Vm.sol";
import { AssetId } from "contracts/src/libraries/AssetId.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { HyperdriveMath } from "contracts/src/libraries/HyperdriveMath.sol";
import { HyperdriveStorage } from "contracts/src/HyperdriveStorage.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { MockHyperdrive, MockHyperdriveDataProvider } from "contracts/test/MockHyperdrive.sol";
import { HyperdriveTest, HyperdriveUtils } from "test/utils/HyperdriveTest.sol";
import { Lib } from "test/utils/Lib.sol";

contract HyperdriveDataProviderTest is HyperdriveTest {
    function testLoadSlots() public {
        uint256[] memory slots = new uint256[](1);
        slots[0] = 15;
        bytes32[] memory values = hyperdrive.load(slots);
        assertEq(address(uint160(uint256(values[0]))), governance);
    }
}
