// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import { IMorpho } from "morpho-blue/src/interfaces/IMorpho.sol";
import { Test } from "forge-std/Test.sol";
import { IPoolAddressesProvider } from "aave/interfaces/IPoolAddressesProvider.sol";
import { ERC4626Hyperdrive } from "../../contracts/src/instances/erc4626/ERC4626Hyperdrive.sol";
import { ERC4626Target0 } from "../../contracts/src/instances/erc4626/ERC4626Target0.sol";
import { ERC4626Target1 } from "../../contracts/src/instances/erc4626/ERC4626Target1.sol";
import { ERC4626Target2 } from "../../contracts/src/instances/erc4626/ERC4626Target2.sol";
import { ERC4626Target3 } from "../../contracts/src/instances/erc4626/ERC4626Target3.sol";
import { ERC4626Target4 } from "../../contracts/src/instances/erc4626/ERC4626Target4.sol";
import { EzETHHyperdrive } from "../../contracts/src/instances/ezeth/EzETHHyperdrive.sol";
import { EzETHTarget0 } from "../../contracts/src/instances/ezeth/EzETHTarget0.sol";
import { EzETHTarget1 } from "../../contracts/src/instances/ezeth/EzETHTarget1.sol";
import { EzETHTarget2 } from "../../contracts/src/instances/ezeth/EzETHTarget2.sol";
import { EzETHTarget3 } from "../../contracts/src/instances/ezeth/EzETHTarget3.sol";
import { EzETHTarget4 } from "../../contracts/src/instances/ezeth/EzETHTarget4.sol";
import { LsETHHyperdrive } from "../../contracts/src/instances/lseth/LsETHHyperdrive.sol";
import { LsETHTarget0 } from "../../contracts/src/instances/lseth/LsETHTarget0.sol";
import { LsETHTarget1 } from "../../contracts/src/instances/lseth/LsETHTarget1.sol";
import { LsETHTarget2 } from "../../contracts/src/instances/lseth/LsETHTarget2.sol";
import { LsETHTarget3 } from "../../contracts/src/instances/lseth/LsETHTarget3.sol";
import { LsETHTarget4 } from "../../contracts/src/instances/lseth/LsETHTarget4.sol";
import { MorphoBlueHyperdrive } from "../../contracts/src/instances/morpho-blue/MorphoBlueHyperdrive.sol";
import { MorphoBlueTarget0 } from "../../contracts/src/instances/morpho-blue/MorphoBlueTarget0.sol";
import { MorphoBlueTarget1 } from "../../contracts/src/instances/morpho-blue/MorphoBlueTarget1.sol";
import { MorphoBlueTarget2 } from "../../contracts/src/instances/morpho-blue/MorphoBlueTarget2.sol";
import { MorphoBlueTarget3 } from "../../contracts/src/instances/morpho-blue/MorphoBlueTarget3.sol";
import { MorphoBlueTarget4 } from "../../contracts/src/instances/morpho-blue/MorphoBlueTarget4.sol";
import { RETHHyperdrive } from "../../contracts/src/instances/reth/RETHHyperdrive.sol";
import { RETHTarget0 } from "../../contracts/src/instances/reth/RETHTarget0.sol";
import { RETHTarget1 } from "../../contracts/src/instances/reth/RETHTarget1.sol";
import { RETHTarget2 } from "../../contracts/src/instances/reth/RETHTarget2.sol";
import { RETHTarget3 } from "../../contracts/src/instances/reth/RETHTarget3.sol";
import { RETHTarget4 } from "../../contracts/src/instances/reth/RETHTarget4.sol";
import { StETHHyperdrive } from "../../contracts/src/instances/steth/StETHHyperdrive.sol";
import { StETHTarget0 } from "../../contracts/src/instances/steth/StETHTarget0.sol";
import { StETHTarget1 } from "../../contracts/src/instances/steth/StETHTarget1.sol";
import { StETHTarget2 } from "../../contracts/src/instances/steth/StETHTarget2.sol";
import { StETHTarget3 } from "../../contracts/src/instances/steth/StETHTarget3.sol";
import { StETHTarget4 } from "../../contracts/src/instances/steth/StETHTarget4.sol";
import { IEzETHHyperdrive } from "../../contracts/src/interfaces/IEzETHHyperdrive.sol";
import { IHyperdrive } from "../../contracts/src/interfaces/IHyperdrive.sol";
import { IHyperdriveAdminController } from "../../contracts/src/interfaces/IHyperdriveAdminController.sol";
import { IMorphoBlueHyperdrive } from "../../contracts/src/interfaces/IMorphoBlueHyperdrive.sol";
import { IRestakeManager } from "../../contracts/src/interfaces/IRenzo.sol";
import { ERC4626_HYPERDRIVE_KIND, EZETH_HYPERDRIVE_KIND, LSETH_HYPERDRIVE_KIND, MORPHO_BLUE_HYPERDRIVE_KIND, RETH_HYPERDRIVE_KIND, STETH_HYPERDRIVE_KIND, VERSION } from "../../contracts/src/libraries/Constants.sol";
import { ERC20Mintable } from "../../contracts/test/ERC20Mintable.sol";
import { EtchingVault } from "../../contracts/test/EtchingVault.sol";
import { MockERC4626 } from "../../contracts/test/MockERC4626.sol";
import { MockEzEthPool } from "../../contracts/test/MockEzEthPool.sol";
import { MockL2Pool } from "../../contracts/test/MockL2Pool.sol";
import { MockLido } from "../../contracts/test/MockLido.sol";
import { MockRocketPool } from "../../contracts/test/MockRocketPool.sol";
import { Lib } from "./Lib.sol";

contract EtchingUtils is Test {
    using Lib for *;

    function etchHyperdrive(
        address _hyperdrive
    ) internal returns (string memory, string memory, string memory) {
        // Ensure that the contract is deployed.
        if (address(_hyperdrive).code.length == 0) {
            revert("EtchingUtils: Empty deployment");
        }

        // Ensure that the contract's version matches.
        IHyperdrive hyperdrive = IHyperdrive(_hyperdrive);
        string memory version = hyperdrive.version();
        if (!hyperdrive.version().eq(VERSION)) {
            revert(
                vm.replace(
                    vm.replace(
                        "EtchingUtils: The checked-out version is %0 but the target version is %1. Consider checking out the target version",
                        "%0",
                        VERSION
                    ),
                    "%1",
                    version
                )
            );
        }

        // Using the name, decide which type of Hyperdrive instance needs to
        // be etched.
        string memory kind = hyperdrive.kind();
        if (kind.eq(ERC4626_HYPERDRIVE_KIND)) {
            etchERC4626Hyperdrive(_hyperdrive);
        } else if (kind.eq(EZETH_HYPERDRIVE_KIND)) {
            etchEzETHHyperdrive(_hyperdrive);
        } else if (kind.eq(LSETH_HYPERDRIVE_KIND)) {
            etchLsETHHyperdrive(_hyperdrive);
        } else if (kind.eq(RETH_HYPERDRIVE_KIND)) {
            etchRETHHyperdrive(_hyperdrive);
        } else if (kind.eq(STETH_HYPERDRIVE_KIND)) {
            etchStETHHyperdrive(_hyperdrive);
        } else if (kind.eq(MORPHO_BLUE_HYPERDRIVE_KIND)) {
            etchMorphoBlueHyperdrive(_hyperdrive);
        } else {
            revert(
                vm.replace(
                    "EtchingUtils: Unrecognized Hyperdrive kind: %0.",
                    "%0",
                    kind
                )
            );
        }

        return (hyperdrive.name(), kind, version);
    }

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

        // TODO: Remove this once we leave testnet.
        //
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
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target0(), address(template).code);
        }

        // Etch the target1 contract.
        {
            ERC4626Target1 template = new ERC4626Target1(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target1(), address(template).code);
        }

        // Etch the target2 contract.
        {
            ERC4626Target2 template = new ERC4626Target2(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target2(), address(template).code);
        }

        // Etch the target3 contract.
        {
            ERC4626Target3 template = new ERC4626Target3(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target3(), address(template).code);
        }

        // Etch the target4 contract.
        {
            ERC4626Target4 template = new ERC4626Target4(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target4(), address(template).code);
        }

        // Etch the hyperdrive contract.
        {
            ERC4626Hyperdrive template = new ERC4626Hyperdrive(
                // NOTE: The name is in storage, so it doesn't matter how we
                // etch it.
                "",
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                hyperdrive.target0(),
                hyperdrive.target1(),
                hyperdrive.target2(),
                hyperdrive.target3(),
                hyperdrive.target4()
            );
            vm.etch(address(hyperdrive), address(template).code);
        }
    }

    function etchEzETHHyperdrive(address _hyperdrive) internal {
        // Get an interface to the target Hyperdrive instance. This will be
        // used to load immutables that will be used during the etching process.
        IEzETHHyperdrive hyperdrive = IEzETHHyperdrive(_hyperdrive);

        // TODO: Remove this once we leave testnet.
        //
        // Etch the vault contract.
        {
            MockEzEthPool target = MockEzEthPool(hyperdrive.vaultSharesToken());
            MockEzEthPool template = new MockEzEthPool(
                0,
                address(0),
                target.isCompetitionMode(),
                target.maxMintAmount()
            );
            vm.etch(address(target), address(template).code);
        }

        // Etch the target0 contract.
        IRestakeManager renzo = hyperdrive.renzo();
        {
            EzETHTarget0 template = new EzETHTarget0(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                renzo
            );
            vm.etch(hyperdrive.target0(), address(template).code);
        }

        // Etch the target1 contract.
        {
            EzETHTarget1 template = new EzETHTarget1(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                renzo
            );
            vm.etch(hyperdrive.target1(), address(template).code);
        }

        // Etch the target2 contract.
        {
            EzETHTarget2 template = new EzETHTarget2(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                renzo
            );
            vm.etch(hyperdrive.target2(), address(template).code);
        }

        // Etch the target3 contract.
        {
            EzETHTarget3 template = new EzETHTarget3(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                renzo
            );
            vm.etch(hyperdrive.target3(), address(template).code);
        }

        // Etch the target4 contract.
        {
            EzETHTarget4 template = new EzETHTarget4(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                renzo
            );
            vm.etch(hyperdrive.target4(), address(template).code);
        }

        // Etch the hyperdrive contract.
        {
            EzETHHyperdrive template = new EzETHHyperdrive(
                // NOTE: The name is in storage, so it doesn't matter how we
                // etch it.
                "",
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                hyperdrive.target0(),
                hyperdrive.target1(),
                hyperdrive.target2(),
                hyperdrive.target3(),
                hyperdrive.target4(),
                renzo
            );
            vm.etch(address(hyperdrive), address(template).code);
        }
    }

    function etchLsETHHyperdrive(address _hyperdrive) internal {
        // Get an interface to the target Hyperdrive instance. This will be
        // used to load immutables that will be used during the etching process.
        IHyperdrive hyperdrive = IHyperdrive(_hyperdrive);

        // Etch the target0 contract.
        {
            LsETHTarget0 template = new LsETHTarget0(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target0(), address(template).code);
        }

        // Etch the target1 contract.
        {
            LsETHTarget1 template = new LsETHTarget1(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target1(), address(template).code);
        }

        // Etch the target2 contract.
        {
            LsETHTarget2 template = new LsETHTarget2(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target2(), address(template).code);
        }

        // Etch the target3 contract.
        {
            LsETHTarget3 template = new LsETHTarget3(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target3(), address(template).code);
        }

        // Etch the target4 contract.
        {
            LsETHTarget4 template = new LsETHTarget4(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target4(), address(template).code);
        }

        // Etch the hyperdrive contract.
        {
            LsETHHyperdrive template = new LsETHHyperdrive(
                // NOTE: The name is in storage, so it doesn't matter how we
                // etch it.
                "",
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                hyperdrive.target0(),
                hyperdrive.target1(),
                hyperdrive.target2(),
                hyperdrive.target3(),
                hyperdrive.target4()
            );
            vm.etch(address(hyperdrive), address(template).code);
        }
    }

    function etchMorphoBlueHyperdrive(address _hyperdrive) internal {
        // Get an interface to the target Hyperdrive instance. This will be
        // used to load immutables that will be used during the etching process.
        IMorphoBlueHyperdrive hyperdrive = IMorphoBlueHyperdrive(_hyperdrive);

        // Get the Morpho Blue parameters.
        IMorphoBlueHyperdrive.MorphoBlueParams
            memory params = IMorphoBlueHyperdrive.MorphoBlueParams({
                morpho: IMorpho(hyperdrive.vault()),
                collateralToken: hyperdrive.collateralToken(),
                oracle: hyperdrive.oracle(),
                irm: hyperdrive.irm(),
                lltv: hyperdrive.lltv()
            });

        // Etch the target0 contract.
        {
            MorphoBlueTarget0 template = new MorphoBlueTarget0(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                params
            );
            vm.etch(hyperdrive.target0(), address(template).code);
        }

        // Etch the target1 contract.
        {
            MorphoBlueTarget1 template = new MorphoBlueTarget1(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                params
            );
            vm.etch(hyperdrive.target1(), address(template).code);
        }

        // Etch the target2 contract.
        {
            MorphoBlueTarget2 template = new MorphoBlueTarget2(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                params
            );
            vm.etch(hyperdrive.target2(), address(template).code);
        }

        // Etch the target3 contract.
        {
            MorphoBlueTarget3 template = new MorphoBlueTarget3(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                params
            );
            vm.etch(hyperdrive.target3(), address(template).code);
        }

        // Etch the target4 contract.
        {
            MorphoBlueTarget4 template = new MorphoBlueTarget4(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                params
            );
            vm.etch(hyperdrive.target4(), address(template).code);
        }

        // Etch the hyperdrive contract.
        {
            MorphoBlueHyperdrive template = new MorphoBlueHyperdrive(
                // NOTE: The name is in storage, so it doesn't matter how we
                // etch it.
                "",
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                hyperdrive.target0(),
                hyperdrive.target1(),
                hyperdrive.target2(),
                hyperdrive.target3(),
                hyperdrive.target4(),
                params
            );
            vm.etch(address(hyperdrive), address(template).code);
        }
    }

    function etchRETHHyperdrive(address _hyperdrive) internal {
        // Get an interface to the target Hyperdrive instance. This will be
        // used to load immutables that will be used during the etching process.
        IHyperdrive hyperdrive = IHyperdrive(_hyperdrive);

        // TODO: Remove this once we leave testnet.
        //
        // Etch the vault contract.
        {
            MockRocketPool target = MockRocketPool(
                hyperdrive.vaultSharesToken()
            );
            MockRocketPool template = new MockRocketPool(
                0,
                address(0),
                target.isCompetitionMode(),
                target.maxMintAmount()
            );
            vm.etch(address(target), address(template).code);
        }

        // Etch the target0 contract.
        {
            RETHTarget0 template = new RETHTarget0(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target0(), address(template).code);
        }

        // Etch the target1 contract.
        {
            RETHTarget1 template = new RETHTarget1(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target1(), address(template).code);
        }

        // Etch the target2 contract.
        {
            RETHTarget2 template = new RETHTarget2(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target2(), address(template).code);
        }

        // Etch the target3 contract.
        {
            RETHTarget3 template = new RETHTarget3(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target3(), address(template).code);
        }

        // Etch the target4 contract.
        {
            RETHTarget4 template = new RETHTarget4(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target4(), address(template).code);
        }

        // Etch the hyperdrive contract.
        {
            RETHHyperdrive template = new RETHHyperdrive(
                // NOTE: The name is in storage, so it doesn't matter how we
                // etch it.
                "",
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
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

        // TODO: Remove this once we leave testnet.
        //
        // Etch the vault contract.
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
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target0(), address(template).code);
        }

        // Etch the target1 contract.
        {
            StETHTarget1 template = new StETHTarget1(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target1(), address(template).code);
        }

        // Etch the target2 contract.
        {
            StETHTarget2 template = new StETHTarget2(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target2(), address(template).code);
        }

        // Etch the target3 contract.
        {
            StETHTarget3 template = new StETHTarget3(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target3(), address(template).code);
        }

        // Etch the target4 contract.
        {
            StETHTarget4 template = new StETHTarget4(
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController())
            );
            vm.etch(hyperdrive.target4(), address(template).code);
        }

        // Etch the hyperdrive contract.
        {
            StETHHyperdrive template = new StETHHyperdrive(
                // NOTE: The name is in storage, so it doesn't matter how we
                // etch it.
                "",
                hyperdrive.getPoolConfig(),
                IHyperdriveAdminController(hyperdrive.adminController()),
                hyperdrive.target0(),
                hyperdrive.target1(),
                hyperdrive.target2(),
                hyperdrive.target3(),
                hyperdrive.target4()
            );
            vm.etch(address(hyperdrive), address(template).code);
        }
    }

    function etchAaveL2Pool(
        address implementationAddress, // Not the proxy, but the implementation address.
        address addressesProvider // The PoolAddressesProvider address used by the pool.
    ) internal {
        MockL2Pool template = new MockL2Pool(
            IPoolAddressesProvider(addressesProvider)
        );
        vm.etch(implementationAddress, address(template).code);
    }
}
