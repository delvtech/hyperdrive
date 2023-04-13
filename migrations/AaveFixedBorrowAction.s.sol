// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { AaveFixedBorrowAction } from "contracts/src/actions/AaveFixedBorrow.sol";
import { IPool } from "@aave/interfaces/IPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Faucet {
    function mint(address token, address to, uint256 amount) external;
}

contract AaveFixedBorrowActionScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // Hyperdrive
        IHyperdrive hyperdrive = IHyperdrive(
            address(0xB311B825171AF5A60d69aAD590B857B1E5ed23a2)
        );

        // Aave Pool
        IPool pool = IPool(address(0x26ca51Af4506DE7a6f0785D20CD776081a05fF6d));

        // AaveFixedBorrow Action Contract
        AaveFixedBorrowAction action = new AaveFixedBorrowAction(
            IHyperdrive(address(hyperdrive)),
            pool
        );

        // Set approvals for supplying, borrowing and shorting
        // Note: Forge struggles with the number the txs in this script. You may
        // have to run it again, commenting out lines that don't need to be
        // repeated, in order to complete the migration.
        IERC20 wsteth = IERC20(
            address(0x6E4F1e8d4c5E5E6e2781FD814EE0744cc16Eb352)
        );
        IERC20 dai = IERC20(
            address(0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844)
        );
        action.setApproval(address(wsteth), address(pool), type(uint256).max);
        action.setApproval(address(dai), address(pool), type(uint256).max);
        action.setApproval(
            address(dai),
            address(hyperdrive),
            type(uint256).max
        );

        vm.stopBroadcast();

        console.log("Deployed AaveFixedBorrowAction to: %s", address(action));
    }
}
