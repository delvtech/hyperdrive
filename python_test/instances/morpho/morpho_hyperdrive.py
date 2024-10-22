import eth_abi
from fixedpointmath import FixedPoint
from hyperdrivetypes.types import (
    HyperdriveFactoryContract,
    IMorphoBlueHyperdrive,
    LPMathContract,
    MorphoBlueConversionsContract,
    MorphoBlueHyperdriveCoreDeployerContract,
    MorphoBlueHyperdriveDeployerCoordinatorContract,
    MorphoBlueTarget0DeployerContract,
    MorphoBlueTarget1DeployerContract,
    MorphoBlueTarget2DeployerContract,
    MorphoBlueTarget3DeployerContract,
    MorphoBlueTarget4DeployerContract,
)
from pypechain.core import dataclass_to_tuple

from ..test_instance import TestInstance


class TestMorphoHyperdrive(TestInstance):
    """This class defines the hyperdrive pool and how to deploy, fund, accumulate interest, etc."""

    def get_extra_data(self) -> bytes:
        tuple_params = dataclass_to_tuple(self.get_morpho_params())
        encoded_market_id = eth_abi.encode(  # type: ignore
            ("address", "address", "address", "address", "uint256"), tuple_params
        )
        return encoded_market_id

    def deploy_coordinator(
        self, factory: HyperdriveFactoryContract, lp_math_contract: LPMathContract
    ) -> MorphoBlueHyperdriveDeployerCoordinatorContract:
        # Morpho also needs morpho blue conversions contract, we deploy this here
        morpho_blue_conversions_contract = MorphoBlueConversionsContract.deploy(self.web3, account=self.alice.account)
        deployer_coordinator = MorphoBlueHyperdriveDeployerCoordinatorContract.deploy(
            self.web3,
            account=self.alice.account,
            constructor_args=MorphoBlueHyperdriveDeployerCoordinatorContract.ConstructorArgs(
                name=self.test_config.name + "DeployerCoordinator",
                factory=factory.address,
                coreDeployer=MorphoBlueHyperdriveCoreDeployerContract.deploy(
                    self.web3,
                    account=self.alice.account,
                ).address,
                target0Deployer=MorphoBlueTarget0DeployerContract.deploy(
                    self.web3,
                    account=self.alice.account,
                    link_references=MorphoBlueTarget0DeployerContract.LinkReferences(
                        MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lp_math_contract
                    ),
                ).address,
                target1Deployer=MorphoBlueTarget1DeployerContract.deploy(
                    self.web3,
                    account=self.alice.account,
                    link_references=MorphoBlueTarget1DeployerContract.LinkReferences(
                        MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lp_math_contract
                    ),
                ).address,
                target2Deployer=MorphoBlueTarget2DeployerContract.deploy(
                    self.web3,
                    account=self.alice.account,
                    link_references=MorphoBlueTarget2DeployerContract.LinkReferences(
                        MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lp_math_contract
                    ),
                ).address,
                target3Deployer=MorphoBlueTarget3DeployerContract.deploy(
                    self.web3,
                    account=self.alice.account,
                    link_references=MorphoBlueTarget3DeployerContract.LinkReferences(
                        MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lp_math_contract
                    ),
                ).address,
                target4Deployer=MorphoBlueTarget4DeployerContract.deploy(
                    self.web3,
                    account=self.alice.account,
                    link_references=MorphoBlueTarget4DeployerContract.LinkReferences(
                        MorphoBlueConversions=morpho_blue_conversions_contract, LPMath=lp_math_contract
                    ),
                ).address,
            ),
            link_references=MorphoBlueHyperdriveDeployerCoordinatorContract.LinkReferences(
                MorphoBlueConversions=morpho_blue_conversions_contract,
            ),
        )

        return deployer_coordinator

    def convert_to_shares(self, base_amount: FixedPoint) -> FixedPoint:
        # TODO
        raise NotImplementedError

    def convert_to_base(self, share_amount: FixedPoint) -> FixedPoint:
        # TODO
        raise NotImplementedError

    # Abstract methods
    def get_morpho_params(self) -> IMorphoBlueHyperdrive.MorphoBlueParams:
        raise NotImplementedError
