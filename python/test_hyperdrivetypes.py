import hyperdrivetypes
from fixedpointmath import FixedPoint


class TestCreateObjects:
    """Test pipeline for creating hyperdrivetype objects."""

    def test_create_checkpointfp_type(self):
        """Creates a CheckpointFP object"""
        checkpoint = hyperdrivetypes.CheckpointFP(FixedPoint(0), 0, FixedPoint(0))

