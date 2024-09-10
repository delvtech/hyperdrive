from agent0 import LocalChain, LocalHyperdrive
from web3 import Web3

from ..test_instance import TestInstance


class AbstractMorphoHyperdrive(TestInstance):
    """This class defines the hyperdrive pool and how to deploy, fund, accumulate interest, etc."""
    def deploy_hyperdrive(self, chain: LocalChain):
        pass
