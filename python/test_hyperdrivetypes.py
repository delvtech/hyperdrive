from eth_typing import ChecksumAddress, HexAddress, HexStr
from hexbytes import HexBytes
from hyperdrivetypes import (
    AddLiquidityEventFP,
    CheckpointFP,
    CloseLongEventFP,
    CloseShortEventFP,
    CreateCheckpointEventFP,
    FeesFP,
    InitializeEventFP,
    OpenLongEventFP,
    OpenShortEventFP,
    PoolConfigFP,
    PoolInfoFP,
    RedeemWithdrawalSharesEventFP,
    RemoveLiquidityEventFP,
)
from hyperdrivetypes.types.IHyperdrive import (
    AddLiquidityEvent,
    Checkpoint,
    CloseLongEvent,
    CloseShortEvent,
    CreateCheckpointEvent,
    Fees,
    InitializeEvent,
    OpenLongEvent,
    OpenShortEvent,
    PoolConfig,
    PoolInfo,
    RedeemWithdrawalSharesEvent,
    RemoveLiquidityEvent,
)

ADDRESS_ZERO = ChecksumAddress(HexAddress(HexStr("0x0000000000000000000000000000000000000000")))


class TestCreateObjects:
    """Test pipeline for creating hyperdrivetype objects."""

    def test_fees_type(self):
        fees = Fees(
            curve=1,
            flat=2,
            governanceLP=3,
            governanceZombie=4,
        )
        fees_fp = FeesFP.from_pypechain(fees)
        test_fees = fees_fp.to_pypechain()
        assert fees == test_fees

    def test_pool_info_type(self):
        pool_info = PoolInfo(
            shareReserves=1,
            shareAdjustment=2,
            zombieBaseProceeds=3,
            zombieShareReserves=4,
            bondReserves=5,
            lpTotalSupply=6,
            vaultSharePrice=7,
            longsOutstanding=8,
            longAverageMaturityTime=9,
            shortsOutstanding=10,
            shortAverageMaturityTime=11,
            withdrawalSharesReadyToWithdraw=12,
            withdrawalSharesProceeds=13,
            lpSharePrice=14,
            longExposure=15,
        )
        pool_info_fp = PoolInfoFP.from_pypechain(pool_info)
        test_pool_info = pool_info_fp.to_pypechain()
        assert pool_info == test_pool_info

    def test_pool_config_type(self):
        pool_config = PoolConfig(
            baseToken="1",
            vaultSharesToken="2",
            linkerFactory="3",
            linkerCodeHash=bytes(4),
            initialVaultSharePrice=5,
            minimumShareReserves=6,
            minimumTransactionAmount=7,
            circuitBreakerDelta=8,
            positionDuration=9,
            checkpointDuration=10,
            timeStretch=11,
            governance="12",
            feeCollector="13",
            sweepCollector="14",
            checkpointRewarder="15",
            fees=Fees(16, 17, 18, 19),
        )
        pool_config_fp = PoolConfigFP.from_pypechain(pool_config)
        test_pool_config = pool_config_fp.to_pypechain()
        assert pool_config == test_pool_config

    def test_checkpoint_type(self):
        checkpoint = Checkpoint(
            weightedSpotPrice=1,
            lastWeightedSpotPriceUpdateTime=2,
            vaultSharePrice=3,
        )
        checkpoint_fp = CheckpointFP.from_pypechain(checkpoint)
        test_checkpoint = checkpoint_fp.to_pypechain()
        assert checkpoint == test_checkpoint

    def test_add_liquidity_event_type(self):
        event = AddLiquidityEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=AddLiquidityEvent.AddLiquidityEventArgs(
                provider="7",
                lpAmount=8,
                amount=9,
                vaultSharePrice=10,
                asBase=True,
                lpSharePrice=12,
                extraData=bytes(13),
            ),
        )
        event_fp = AddLiquidityEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event

    def test_close_long_event_type(self):
        event = CloseLongEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=CloseLongEvent.CloseLongEventArgs(
                trader="7",
                destination="8",
                assetId=9,
                maturityTime=10,
                amount=11,
                vaultSharePrice=12,
                asBase=True,
                bondAmount=14,
                extraData=bytes(15),
            ),
        )
        event_fp = CloseLongEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event

    def test_close_short_event_type(self):
        event = CloseShortEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=CloseShortEvent.CloseShortEventArgs(
                trader="7",
                destination="8",
                assetId=9,
                maturityTime=10,
                amount=11,
                vaultSharePrice=12,
                asBase=True,
                basePayment=14,
                bondAmount=15,
                extraData=bytes(16),
            ),
        )

        event_fp = CloseShortEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event

    def test_create_checkpoint_event_type(self):
        event = CreateCheckpointEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=CreateCheckpointEvent.CreateCheckpointEventArgs(
                checkpointTime=7,
                checkpointVaultSharePrice=7,
                vaultSharePrice=8,
                maturedShorts=9,
                maturedLongs=10,
                lpSharePrice=11,
            ),
        )

        event_fp = CreateCheckpointEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event

    def test_initialize_event_type(self):
        event = InitializeEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=InitializeEvent.InitializeEventArgs(
                provider="7",
                lpAmount=8,
                amount=9,
                vaultSharePrice=10,
                asBase=True,
                apr=11,
                extraData=bytes(12),
            ),
        )

        event_fp = InitializeEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event

    def test_open_long_event_type(self):
        event = OpenLongEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=OpenLongEvent.OpenLongEventArgs(
                trader="7",
                assetId=8,
                maturityTime=9,
                amount=10,
                vaultSharePrice=11,
                asBase=True,
                bondAmount=13,
                extraData=bytes(14),
            ),
        )

        event_fp = OpenLongEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event

    def test_open_short_event_type(self):
        event = OpenShortEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=OpenShortEvent.OpenShortEventArgs(
                trader="7",
                assetId=8,
                maturityTime=9,
                amount=10,
                vaultSharePrice=11,
                asBase=True,
                baseProceeds=13,
                bondAmount=14,
                extraData=bytes(15),
            ),
        )

        event_fp = OpenShortEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event

    def test_redeem_withdrawal_shares_event_type(self):
        event = RedeemWithdrawalSharesEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=RedeemWithdrawalSharesEvent.RedeemWithdrawalSharesEventArgs(
                provider="7",
                destination="8",
                withdrawalShareAmount=9,
                amount=10,
                vaultSharePrice=11,
                asBase=True,
                extraData=bytes(12),
            ),
        )

        event_fp = RedeemWithdrawalSharesEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event

    def test_remove_liquidity_event_type(self):
        event = RemoveLiquidityEvent(
            log_index=1,
            transaction_index=2,
            transaction_hash=HexBytes("3"),
            address=ADDRESS_ZERO,
            block_hash=HexBytes("5"),
            block_number=6,
            args=RemoveLiquidityEvent.RemoveLiquidityEventArgs(
                provider="7",
                destination="8",
                lpAmount=9,
                amount=10,
                vaultSharePrice=11,
                asBase=True,
                withdrawalShareAmount=12,
                lpSharePrice=13,
                extraData=bytes(14),
            ),
        )

        event_fp = RemoveLiquidityEventFP.from_pypechain(event)
        test_event = event_fp.to_pypechain()
        assert event == test_event
