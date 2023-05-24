// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import { FixedPointMath } from "contracts/src/libraries/FixedPointMath.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { HyperdriveUtils } from "test/utils/HyperdriveUtils.sol";
import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract HyperdriveInitialize is Script {
    using FixedPointMath for uint256;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        IHyperdrive hyperdrive = IHyperdrive(
            address(0xB311B825171AF5A60d69aAD590B857B1E5ed23a2)
        );
        IERC20 baseToken = IERC20(hyperdrive.baseToken());
        // Initialize Hyperdrive to have an APR equal to 1%.
        uint256 apr = 0.01e18;
        uint256 contribution = 50_000e18;
        baseToken.approve(address(hyperdrive), contribution);
        hyperdrive.initialize(contribution, apr, deployerAddress, true);

        vm.stopBroadcast();
    }
}
