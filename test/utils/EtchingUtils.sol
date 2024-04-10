// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import { Test } from "forge-std/Test.sol";
import { ERC4626Hyperdrive } from "contracts/src/instances/erc4626/ERC4626Hyperdrive.sol";
import { ERC4626Target0 } from "contracts/src/instances/erc4626/ERC4626Target0.sol";
import { ERC4626Target1 } from "contracts/src/instances/erc4626/ERC4626Target1.sol";
import { ERC4626Target2 } from "contracts/src/instances/erc4626/ERC4626Target2.sol";
import { ERC4626Target3 } from "contracts/src/instances/erc4626/ERC4626Target3.sol";
import { ERC4626Target4 } from "contracts/src/instances/erc4626/ERC4626Target4.sol";
import { StETHHyperdrive } from "contracts/src/instances/steth/StETHHyperdrive.sol";
import { StETHTarget0 } from "contracts/src/instances/steth/StETHTarget0.sol";
import { StETHTarget1 } from "contracts/src/instances/steth/StETHTarget1.sol";
import { StETHTarget2 } from "contracts/src/instances/steth/StETHTarget2.sol";
import { StETHTarget3 } from "contracts/src/instances/steth/StETHTarget3.sol";
import { StETHTarget4 } from "contracts/src/instances/steth/StETHTarget4.sol";
import { IHyperdrive } from "contracts/src/interfaces/IHyperdrive.sol";
import { ERC20Mintable } from "contracts/test/ERC20Mintable.sol";
import { EtchingVault } from "contracts/test/EtchingVault.sol";
import { MockLido } from "contracts/test/MockLido.sol";
import { MockERC4626 } from "contracts/test/MockERC4626.sol";

contract EtchingUtils is Test {
    function etchERC4626Hyperdrive(address _hyperdrive) internal {
        // Get an interface to the target Hyperdrive instance. This will be
        // used to load immutables that will be used during the etching process.
        IHyperdrive hyperdrive = IHyperdrive(_hyperdrive);

        // Etch the base contract.
        {
            ERC20Mintable target = ERC20Mintable(hyperdrive.baseToken());
            ERC20Mintable template = new ERC20Mintable(
                target.name(),
                target.symbol(),
                target.decimals(),
                address(0),
                target.isCompetitionMode(),
                target.maxMintAmount()
            );
            vm.etch(address(target), address(template).code);
        }

        // Etch the vault contract.
        {
            MockERC4626 target = MockERC4626(hyperdrive.vaultSharesToken());
            MockERC4626 template = new MockERC4626(
                ERC20Mintable(address(target.asset())),
                target.name(),
                target.symbol(),
                0,
                address(0),
                target.isCompetitionMode(),
                target.maxMintAmount()
            );
            vm.etch(address(target), address(template).code);
        }

        // Etch the target0 contract.
        {
            ERC4626Target0 template = new ERC4626Target0(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target0(), address(template).code);
        }

        // Etch the target1 contract.
        {
            ERC4626Target1 template = new ERC4626Target1(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target1(), address(template).code);
        }

        // Etch the target2 contract.
        {
            ERC4626Target2 template = new ERC4626Target2(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target2(), address(template).code);
        }

        // Etch the target3 contract.
        {
            ERC4626Target3 template = new ERC4626Target3(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target3(), address(template).code);
        }

        // Etch the target4 contract.
        {
            ERC4626Target4 template = new ERC4626Target4(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target4(), address(template).code);
        }

        // Etch the hyperdrive contract.
        {
            ERC4626Hyperdrive template = new ERC4626Hyperdrive(
                hyperdrive.getPoolConfig(),
                hyperdrive.target0(),
                hyperdrive.target1(),
                hyperdrive.target2(),
                hyperdrive.target3(),
                hyperdrive.target4()
            );
            vm.etch(address(hyperdrive), address(template).code);
        }
    }

    function etchStETHHyperdrive(address _hyperdrive) internal {
        // Get an interface to the target Hyperdrive instance. This will be
        // used to load immutables that will be used during the etching process.
        IHyperdrive hyperdrive = IHyperdrive(_hyperdrive);

        // Etch the vault contract.        {
        {
            MockLido target = MockLido(hyperdrive.vaultSharesToken());
            MockLido template = new MockLido(
                0,
                address(0),
                target.isCompetitionMode(),
                target.maxMintAmount()
            );
            vm.etch(address(target), address(template).code);
        }

        // Etch the target0 contract.
        {
            StETHTarget0 template = new StETHTarget0(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target0(), address(template).code);
        }

        // Etch the target1 contract.
        {
            StETHTarget1 template = new StETHTarget1(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target1(), address(template).code);
        }

        // Etch the target2 contract.
        {
            StETHTarget2 template = new StETHTarget2(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target2(), address(template).code);
        }

        // Etch the target3 contract.
        {
            StETHTarget3 template = new StETHTarget3(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target3(), address(template).code);
        }

        // Etch the target4 contract.
        {
            StETHTarget4 template = new StETHTarget4(
                hyperdrive.getPoolConfig()
            );
            vm.etch(hyperdrive.target4(), address(template).code);
        }

        // Etch the hyperdrive contract.
        {
            StETHHyperdrive template = new StETHHyperdrive(
                hyperdrive.getPoolConfig(),
                hyperdrive.target0(),
                hyperdrive.target1(),
                hyperdrive.target2(),
                hyperdrive.target3(),
                hyperdrive.target4()
            );
            vm.etch(address(hyperdrive), address(template).code);
        }
    }
}
