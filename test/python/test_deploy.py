"""Test simple ape deployment"""
from pathlib import Path

from ape import Project, accounts, networks


def test_deploy():
    # ## Compilation and Network Setup
    networks.parse_network_choice("ethereum:local:foundry").__enter__()
    project_root = Path.cwd().parent
    project = Project(path=project_root)

    # deployment config values
    base_supply = int(1e23)  # 100k
    t_stretch = int(1 / 22.186877016851916266 * 10**18)
    initial_apr = int(0.05e18)
    share_price = int(1e18)
    checkpoints = 365
    checkpoint_duration = 86400
    curve_fee = 0
    flat_fee = 0
    gov_fee = 0

    # generate deployer account
    deployer = accounts.test_accounts.generate_test_account()

    # give deployer 3 eth
    deployer.balance += int(3e18)

    base_address = deployer.deploy(project.ERC20Mintable)
    base_ERC20 = project.ERC20Mintable.at(base_address)

    fixed_math_address = deployer.deploy(project.MockFixedPointMath)
    fixed_math = project.MockFixedPointMath.at(fixed_math_address)

    base_ERC20.mint(base_supply, sender=deployer)
    time_stretch = fixed_math.divDown(int(1e18), t_stretch)

    hyperdrive_data_provider_address = deployer.deploy(
        project.MockHyperdriveDataProviderTestnet,
        base_ERC20,
    )
    hyperdrive_address = deployer.deploy(
        project.MockHyperdriveTestnet,
        hyperdrive_data_provider_address,
        base_ERC20,
        initial_apr,
        share_price,
        checkpoints,
        checkpoint_duration,
        int(time_stretch),
        (curve_fee, flat_fee, gov_fee),
        deployer,
    )
    hyperdrive = project.MockHyperdriveTestnet.at(hyperdrive_address)

    with accounts.use_sender(deployer):
        base_ERC20.approve(hyperdrive, base_supply)
        hyperdrive.initialize(base_supply, initial_apr, deployer, True)
