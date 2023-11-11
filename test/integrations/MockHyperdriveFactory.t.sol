// // SPDX-License-Identifier: Apache-2.0
// pragma solidity 0.8.19;

// import { HyperdriveFactory } from "contracts/src/factory/HyperdriveFactory.sol";
// import { IERC20 } from "contracts/src/interfaces/IERC20.sol";
// import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
// import { IHyperdriveDeployer } from "contracts/src/interfaces/IHyperdriveDeployer.sol";
// import { AssetId } from "contracts/src/libraries/AssetId.sol";
// import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
// import { ForwarderFactory } from "contracts/src/token/ForwarderFactory.sol";
// import { HyperdriveTest } from "../utils/HyperdriveTest.sol";
// import { HyperdriveUtils } from "../utils/HyperdriveUtils.sol";
// import { MockHyperdriveFactory } from "../mocks/MockHyperdriveFactory.sol";

// contract MockHyperdriveFactoryTest is HyperdriveTest {
//     function test_hyperdrive_factory_fees() external {
//         address[] memory defaults = new address[](1);
//         defaults[0] = bob;
//         IHyperdriveDeployer simpleDeployer;
//         MockHyperdriveFactory factory = new MockHyperdriveFactory(
//             HyperdriveFactory.FactoryConfig(
//                 alice,
//                 bob,
//                 bob,
//                 IHyperdrive.Fees(0, 0, 0),
//                 IHyperdrive.Fees(0, 0, 0),
//                 defaults
//             ),
//             simpleDeployer,
//             address(0),
//             bytes32(0)
//         );

//         assertEq(factory.governance(), alice);
//         vm.startPrank(alice);

//         // Curve fee can not exceed maximum curve fee.
//         vm.expectRevert(IHyperdrive.FeeTooHigh.selector);
//         factory.updateFees(IHyperdrive.Fees(2e18, 0, 0));

//         // Flat fee can not exceed maximum flat fee.
//         vm.expectRevert(IHyperdrive.FeeTooHigh.selector);
//         factory.updateFees(IHyperdrive.Fees(0, 2e18, 0));

//         // Governance fee can not exceed maximum governance fee.
//         vm.expectRevert(IHyperdrive.FeeTooHigh.selector);
//         factory.updateFees(IHyperdrive.Fees(0, 0, 2e18));
//     }

//     // Ensure that the maximum curve fee can not exceed 100%.
//     function test_hyperdrive_factory_max_fees() external {
//         address[] memory defaults = new address[](1);
//         defaults[0] = bob;
//         IHyperdriveDeployer simpleDeployer;

//         // Ensure that the maximum curve fee can not exceed 100%.
//         vm.expectRevert(IHyperdrive.MaxFeeTooHigh.selector);
//         new MockHyperdriveFactory(
//             HyperdriveFactory.FactoryConfig(
//                 alice,
//                 bob,
//                 bob,
//                 IHyperdrive.Fees(0, 0, 0),
//                 IHyperdrive.Fees(2e18, 0, 0),
//                 defaults
//             ),
//             simpleDeployer,
//             address(0),
//             bytes32(0)
//         );

//         // Ensure that the maximum flat fee can not exceed 100%.
//         vm.expectRevert(IHyperdrive.MaxFeeTooHigh.selector);
//         new MockHyperdriveFactory(
//             HyperdriveFactory.FactoryConfig(
//                 alice,
//                 bob,
//                 bob,
//                 IHyperdrive.Fees(0, 0, 0),
//                 IHyperdrive.Fees(0, 2e18, 0),
//                 defaults
//             ),
//             simpleDeployer,
//             address(0),
//             bytes32(0)
//         );

//         // Ensure that the maximum governance fee can not exceed 100%.
//         vm.expectRevert(IHyperdrive.MaxFeeTooHigh.selector);
//         new MockHyperdriveFactory(
//             HyperdriveFactory.FactoryConfig(
//                 alice,
//                 bob,
//                 bob,
//                 IHyperdrive.Fees(0, 0, 0),
//                 IHyperdrive.Fees(0, 0, 2e18),
//                 defaults
//             ),
//             simpleDeployer,
//             address(0),
//             bytes32(0)
//         );
//     }
// }


// TODO: Determine if this file is necessary anymore
