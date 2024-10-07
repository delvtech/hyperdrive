"""Fixed point versions of common structs from the hyperdrive contracts."""

from __future__ import annotations

from dataclasses import dataclass

from fixedpointmath import FixedPoint
from hyperdrivetypes.types.IHyperdriveTypes import (
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
from pypechain.core import BaseEventArgs

# TODO: These dataclasses are similar to pypechain except for
#  - snake_case attributes instead of camelCase
#  - FixedPoint types instead of int
#  - Helper factory function for each corresponding pypechain type for conversions
#
# We'd like to rely on the pypechain classes as much as possible.
# One solution could be to build our own interface wrapper that pulls in the pypechain
# dataclass and makes this fixed set of changes?
# pylint: disable=too-many-instance-attributes

# We overwrite the args nested dataclass in events to change their type from
# the original pypechain type to the fixed point type.
# type: ignore[override]


@dataclass
class FeesFP:
    """Fees struct."""

    curve: FixedPoint
    flat: FixedPoint
    governance_lp: FixedPoint
    governance_zombie: FixedPoint

    @classmethod
    def from_pypechain(cls, in_val: Fees) -> FeesFP:
        """Convert a pypechain Fees object to a fixed point FeesFP object.

        Arguments
        ---------
        in_val: Fees
            The pypechain Fees object to convert.

        Returns
        -------
        FeesFP
            The converted fixed point FeesFP object.
        """
        # We do this statically to ensure everything gets typed checked.
        return FeesFP(
            curve=FixedPoint(scaled_value=in_val.curve),
            flat=FixedPoint(scaled_value=in_val.flat),
            governance_lp=FixedPoint(scaled_value=in_val.governanceLP),
            governance_zombie=FixedPoint(scaled_value=in_val.governanceZombie),
        )

    def to_pypechain(self) -> Fees:
        """Convert a fixed point FeesFP object to a pypechain Fees object.

        Returns
        -------
        Fees
            The converted pypechain Fees object.
        """
        return Fees(
            curve=self.curve.scaled_value,
            flat=self.flat.scaled_value,
            governanceLP=self.governance_lp.scaled_value,
            governanceZombie=self.governance_zombie.scaled_value,
        )


@dataclass
class PoolInfoFP:
    """PoolInfo struct."""

    share_reserves: FixedPoint
    share_adjustment: FixedPoint
    zombie_base_proceeds: FixedPoint
    zombie_share_reserves: FixedPoint
    bond_reserves: FixedPoint
    lp_total_supply: FixedPoint
    vault_share_price: FixedPoint
    longs_outstanding: FixedPoint
    long_average_maturity_time: FixedPoint
    shorts_outstanding: FixedPoint
    short_average_maturity_time: FixedPoint
    withdrawal_shares_ready_to_withdraw: FixedPoint
    withdrawal_shares_proceeds: FixedPoint
    lp_share_price: FixedPoint
    long_exposure: FixedPoint

    @classmethod
    def from_pypechain(cls, in_val: PoolInfo) -> PoolInfoFP:
        """Convert a pypechain PoolInfo object to a fixed point PoolInfoFP object.

        Arguments
        ---------
        in_val: PoolInfo
            The pypechain PoolInfo object to convert.

        Returns
        -------
        PoolInfoFP
            The converted fixed point PoolInfoFP object.
        """

        return PoolInfoFP(
            share_reserves=FixedPoint(scaled_value=in_val.shareReserves),
            share_adjustment=FixedPoint(scaled_value=in_val.shareAdjustment),
            zombie_base_proceeds=FixedPoint(scaled_value=in_val.zombieBaseProceeds),
            zombie_share_reserves=FixedPoint(scaled_value=in_val.zombieShareReserves),
            bond_reserves=FixedPoint(scaled_value=in_val.bondReserves),
            lp_share_price=FixedPoint(scaled_value=in_val.lpSharePrice),
            vault_share_price=FixedPoint(scaled_value=in_val.vaultSharePrice),
            longs_outstanding=FixedPoint(scaled_value=in_val.longsOutstanding),
            long_average_maturity_time=FixedPoint(scaled_value=in_val.longAverageMaturityTime),
            shorts_outstanding=FixedPoint(scaled_value=in_val.shortsOutstanding),
            short_average_maturity_time=FixedPoint(scaled_value=in_val.shortAverageMaturityTime),
            withdrawal_shares_ready_to_withdraw=FixedPoint(scaled_value=in_val.withdrawalSharesReadyToWithdraw),
            withdrawal_shares_proceeds=FixedPoint(scaled_value=in_val.withdrawalSharesProceeds),
            lp_total_supply=FixedPoint(scaled_value=in_val.lpTotalSupply),
            long_exposure=FixedPoint(scaled_value=in_val.longExposure),
        )

    def to_pypechain(self) -> PoolInfo:
        """Convert a fixed point PoolInfoFP object to a pypechain PoolInfo object.

        Returns
        -------
        PoolInfo
            The converted pypechain PoolInfo object.
        """

        return PoolInfo(
            shareReserves=self.share_reserves.scaled_value,
            shareAdjustment=self.share_adjustment.scaled_value,
            zombieBaseProceeds=self.zombie_base_proceeds.scaled_value,
            zombieShareReserves=self.zombie_share_reserves.scaled_value,
            bondReserves=self.bond_reserves.scaled_value,
            lpTotalSupply=self.lp_total_supply.scaled_value,
            vaultSharePrice=self.vault_share_price.scaled_value,
            longsOutstanding=self.longs_outstanding.scaled_value,
            longAverageMaturityTime=self.long_average_maturity_time.scaled_value,
            shortsOutstanding=self.shorts_outstanding.scaled_value,
            shortAverageMaturityTime=self.short_average_maturity_time.scaled_value,
            withdrawalSharesReadyToWithdraw=self.withdrawal_shares_ready_to_withdraw.scaled_value,
            withdrawalSharesProceeds=self.withdrawal_shares_proceeds.scaled_value,
            lpSharePrice=self.lp_share_price.scaled_value,
            longExposure=self.long_exposure.scaled_value,
        )


@dataclass
class PoolConfigFP:
    """PoolConfig struct."""

    base_token: str
    vault_shares_token: str
    linker_factory: str
    linker_code_hash: bytes
    initial_vault_share_price: FixedPoint
    minimum_share_reserves: FixedPoint
    minimum_transaction_amount: FixedPoint
    circuit_breaker_delta: FixedPoint
    position_duration: int
    checkpoint_duration: int
    time_stretch: FixedPoint
    governance: str
    fee_collector: str
    sweep_collector: str
    checkpoint_rewarder: str
    fees: FeesFP

    @classmethod
    def from_pypechain(cls, in_val: PoolConfig) -> PoolConfigFP:
        """Convert a pypechain PoolConfig object to a fixed point PoolConfigFP object.

        Arguments
        ---------
        in_val: PoolConfig
            The pypechain PoolConfig object to convert.

        Returns
        -------
        PoolConfigFP
            The converted fixed point PoolConfigFP object.
        """

        return PoolConfigFP(
            base_token=in_val.baseToken,
            vault_shares_token=in_val.vaultSharesToken,
            linker_factory=in_val.linkerFactory,
            linker_code_hash=in_val.linkerCodeHash,
            initial_vault_share_price=FixedPoint(scaled_value=in_val.initialVaultSharePrice),
            minimum_share_reserves=FixedPoint(scaled_value=in_val.minimumShareReserves),
            minimum_transaction_amount=FixedPoint(scaled_value=in_val.minimumTransactionAmount),
            circuit_breaker_delta=FixedPoint(scaled_value=in_val.circuitBreakerDelta),
            position_duration=in_val.positionDuration,
            checkpoint_duration=in_val.checkpointDuration,
            time_stretch=FixedPoint(scaled_value=in_val.timeStretch),
            governance=in_val.governance,
            fee_collector=in_val.feeCollector,
            sweep_collector=in_val.sweepCollector,
            checkpoint_rewarder=in_val.checkpointRewarder,
            fees=FeesFP.from_pypechain(in_val.fees),
        )

    def to_pypechain(self) -> PoolConfig:
        """Convert a fixed point PoolConfigFP object to a pypechain PoolConfig object.

        Returns
        -------
        PoolConfig
            The converted pypechain PoolConfig object.
        """

        return PoolConfig(
            baseToken=self.base_token,
            vaultSharesToken=self.vault_shares_token,
            linkerFactory=self.linker_factory,
            linkerCodeHash=self.linker_code_hash,
            initialVaultSharePrice=self.initial_vault_share_price.scaled_value,
            minimumShareReserves=self.minimum_share_reserves.scaled_value,
            minimumTransactionAmount=self.minimum_transaction_amount.scaled_value,
            circuitBreakerDelta=self.circuit_breaker_delta.scaled_value,
            positionDuration=self.position_duration,
            checkpointDuration=self.checkpoint_duration,
            timeStretch=self.time_stretch.scaled_value,
            governance=self.governance,
            feeCollector=self.fee_collector,
            sweepCollector=self.sweep_collector,
            checkpointRewarder=self.checkpoint_rewarder,
            fees=self.fees.to_pypechain(),
        )


@dataclass
class CheckpointFP:
    """Checkpoint struct."""

    weighted_spot_price: FixedPoint
    last_weighted_spot_price_update_time: int
    vault_share_price: FixedPoint

    @classmethod
    def from_pypechain(cls, in_val: Checkpoint) -> CheckpointFP:
        """Convert a pypechain Checkpoint object to a fixed point CheckpointFP object.

        Arguments
        ---------
        in_val: Checkpoint
            The pypechain Checkpoint object to convert.

        Returns
        -------
        CheckpointFP
            The converted fixed point CheckpointFP object.
        """

        return CheckpointFP(
            weighted_spot_price=FixedPoint(scaled_value=in_val.weightedSpotPrice),
            last_weighted_spot_price_update_time=in_val.lastWeightedSpotPriceUpdateTime,
            vault_share_price=FixedPoint(scaled_value=in_val.vaultSharePrice),
        )

    def to_pypechain(self) -> Checkpoint:
        """Convert a fixed point CheckpointFP object to a pypechain Checkpoint object.

        Returns
        -------
        Checkpoint
            The converted pypechain Checkpoint object.
        """

        return Checkpoint(
            weightedSpotPrice=self.weighted_spot_price.scaled_value,
            lastWeightedSpotPriceUpdateTime=self.last_weighted_spot_price_update_time,
            vaultSharePrice=self.vault_share_price.scaled_value,
        )


# Event classes
# We subclass from the original event class keep most other arguments,
# but change the event args class and redefine to be snake case and fixed point.
# the args type


@dataclass(kw_only=True)
class AddLiquidityEventFP(AddLiquidityEvent):
    """Add liquidity event."""

    @dataclass(kw_only=True)
    class AddLiquidityEventArgsFP(BaseEventArgs):
        """The args to the event AddLiquidity"""

        provider: str
        lp_amount: FixedPoint
        amount: FixedPoint
        vault_share_price: FixedPoint
        as_base: bool
        lp_share_price: FixedPoint
        extra_data: bytes

    # We redefine the type in the subclass
    args: AddLiquidityEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: AddLiquidityEvent) -> AddLiquidityEventFP:
        """Convert a pypechain AddLiquidityEvent object to a fixed point AddLiquidityEventFP object.

        Arguments
        ---------
        in_val: AddLiquidityEvent
            The pypechain AddLiquidityEvent object to convert.

        Returns
        -------
        AddLiquidityEventFP
            The converted fixed point AddLiquidityEventFP object.
        """

        return AddLiquidityEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=AddLiquidityEventFP.AddLiquidityEventArgsFP(
                provider=in_val.args.provider,
                lp_amount=FixedPoint(scaled_value=in_val.args.lpAmount),
                amount=FixedPoint(scaled_value=in_val.args.amount),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                as_base=in_val.args.asBase,
                lp_share_price=FixedPoint(scaled_value=in_val.args.lpSharePrice),
                extra_data=in_val.args.extraData,
            ),
        )

    def to_pypechain(self) -> AddLiquidityEvent:
        """Convert a fixed point AddLiquidityEventFP object to a pypechain AddLiquidityEvent object.

        Returns
        -------
        AddLiquidityEvent
            The converted pypechain AddLiquidityEvent object.
        """

        return AddLiquidityEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=AddLiquidityEvent.AddLiquidityEventArgs(
                provider=self.args.provider,
                lpAmount=self.args.lp_amount.scaled_value,
                amount=self.args.amount.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                asBase=self.args.as_base,
                lpSharePrice=self.args.lp_share_price.scaled_value,
                extraData=self.args.extra_data,
            ),
        )


@dataclass(kw_only=True)
class CloseLongEventFP(CloseLongEvent):
    """CloseLong event."""

    @dataclass(kw_only=True)
    class CloseLongEventArgsFP(BaseEventArgs):
        """The args to the event CloseLong"""

        trader: str
        destination: str
        asset_id: int
        maturity_time: int
        amount: FixedPoint
        vault_share_price: FixedPoint
        as_base: bool
        bond_amount: FixedPoint
        extra_data: bytes

    # We redefine the type in the subclass
    args: CloseLongEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: CloseLongEvent) -> CloseLongEventFP:
        """Convert a pypechain CloseLongEvent object to a fixed point CloseLongEventFP object.

        Arguments
        ---------
        in_val: CloseLongEvent
            The pypechain CloseLongEvent object to convert.

        Returns
        -------
        CloseLongEventFP
            The converted fixed point CloseLongEventFP object.
        """

        return CloseLongEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=CloseLongEventFP.CloseLongEventArgsFP(
                trader=in_val.args.trader,
                destination=in_val.args.destination,
                asset_id=in_val.args.assetId,
                maturity_time=in_val.args.maturityTime,
                amount=FixedPoint(scaled_value=in_val.args.amount),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                as_base=in_val.args.asBase,
                bond_amount=FixedPoint(scaled_value=in_val.args.bondAmount),
                extra_data=in_val.args.extraData,
            ),
        )

    def to_pypechain(self) -> CloseLongEvent:
        """Convert a fixed point CloseLongEventFP object to a pypechain CloseLongEvent object.

        Returns
        -------
        CloseLongEvent
            The converted pypechain CloseLongEvent object.
        """

        return CloseLongEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=CloseLongEvent.CloseLongEventArgs(
                trader=self.args.trader,
                destination=self.args.destination,
                assetId=self.args.asset_id,
                maturityTime=self.args.maturity_time,
                amount=self.args.amount.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                asBase=self.args.as_base,
                bondAmount=self.args.bond_amount.scaled_value,
                extraData=self.args.extra_data,
            ),
        )


@dataclass(kw_only=True)
class CloseShortEventFP(CloseShortEvent):
    """CloseShort event."""

    @dataclass(kw_only=True)
    class CloseShortEventArgsFP(BaseEventArgs):
        """The args to the event CloseShort"""

        trader: str
        destination: str
        asset_id: int
        maturity_time: int
        amount: FixedPoint
        vault_share_price: FixedPoint
        as_base: bool
        base_payment: FixedPoint
        bond_amount: FixedPoint
        extra_data: bytes

    # We redefine the type in the subclass
    args: CloseShortEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: CloseShortEvent) -> CloseShortEventFP:
        """Convert a pypechain CloseShortEvent object to a fixed point CloseShortEventFP object.

        Arguments
        ---------
        in_val: CloseShortEvent
            The pypechain CloseShortEvent object to convert.

        Returns
        -------
        CloseShortEventFP
            The converted fixed point CloseShortEventFP object.
        """

        return CloseShortEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=CloseShortEventFP.CloseShortEventArgsFP(
                trader=in_val.args.trader,
                destination=in_val.args.destination,
                asset_id=in_val.args.assetId,
                maturity_time=in_val.args.maturityTime,
                amount=FixedPoint(scaled_value=in_val.args.amount),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                as_base=in_val.args.asBase,
                base_payment=FixedPoint(scaled_value=in_val.args.basePayment),
                bond_amount=FixedPoint(scaled_value=in_val.args.bondAmount),
                extra_data=in_val.args.extraData,
            ),
        )

    def to_pypechain(self) -> CloseShortEvent:
        """Convert a fixed point CloseShortEventFP object to a pypechain CloseShortEvent object.

        Returns
        -------
        CloseShortEvent
            The converted pypechain CloseShortEvent object.
        """

        return CloseShortEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=CloseShortEvent.CloseShortEventArgs(
                trader=self.args.trader,
                destination=self.args.destination,
                assetId=self.args.asset_id,
                maturityTime=self.args.maturity_time,
                amount=self.args.amount.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                asBase=self.args.as_base,
                basePayment=self.args.base_payment.scaled_value,
                bondAmount=self.args.bond_amount.scaled_value,
                extraData=self.args.extra_data,
            ),
        )


@dataclass(kw_only=True)
class CreateCheckpointEventFP(CreateCheckpointEvent):
    """CreateCheckpoint event."""

    @dataclass(kw_only=True)
    class CreateCheckpointEventArgsFP(BaseEventArgs):
        """The args to the event CreateCheckpoint"""

        checkpoint_time: int
        checkpoint_vault_share_price: FixedPoint
        vault_share_price: FixedPoint
        matured_shorts: FixedPoint
        matured_longs: FixedPoint
        lp_share_price: FixedPoint

    # We redefine the type in the subclass
    args: CreateCheckpointEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: CreateCheckpointEvent) -> CreateCheckpointEventFP:
        """Convert a pypechain CreateCheckpointEvent object to a fixed point CreateCheckpointEventFP object.

        Arguments
        ---------
        in_val: CreateCheckpointEvent
            The pypechain CreateCheckpointEvent object to convert.

        Returns
        -------
        CreateCheckpointEventFP
            The converted fixed point CreateCheckpointEventFP object.
        """

        return CreateCheckpointEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=CreateCheckpointEventFP.CreateCheckpointEventArgsFP(
                checkpoint_time=in_val.args.checkpointTime,
                checkpoint_vault_share_price=FixedPoint(scaled_value=in_val.args.checkpointVaultSharePrice),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                matured_shorts=FixedPoint(scaled_value=in_val.args.maturedShorts),
                matured_longs=FixedPoint(scaled_value=in_val.args.maturedLongs),
                lp_share_price=FixedPoint(scaled_value=in_val.args.lpSharePrice),
            ),
        )

    def to_pypechain(self) -> CreateCheckpointEvent:
        """Convert a fixed point CreateCheckpointEventFP object to a pypechain CreateCheckpointEvent object.

        Returns
        -------
        CreateCheckpointEvent
            The converted pypechain CreateCheckpointEvent object.
        """

        return CreateCheckpointEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=CreateCheckpointEvent.CreateCheckpointEventArgs(
                checkpointTime=self.args.checkpoint_time,
                checkpointVaultSharePrice=self.args.checkpoint_vault_share_price.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                maturedShorts=self.args.matured_shorts.scaled_value,
                maturedLongs=self.args.matured_longs.scaled_value,
                lpSharePrice=self.args.lp_share_price.scaled_value,
            ),
        )


@dataclass(kw_only=True)
class InitializeEventFP(InitializeEvent):
    """InitializeEvent event."""

    @dataclass(kw_only=True)
    class InitializeEventArgsFP(BaseEventArgs):
        """The args to the event InitializeEvent"""

        provider: str
        lp_amount: FixedPoint
        amount: FixedPoint
        vault_share_price: FixedPoint
        as_base: bool
        apr: FixedPoint
        extra_data: bytes

    # We redefine the type in the subclass
    args: InitializeEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: InitializeEvent) -> InitializeEventFP:
        """Convert a pypechain InitializeEvent object to a fixed point InitializeEventFP object.

        Arguments
        ---------
        in_val: InitializeEvent
            The pypechain InitializeEvent object to convert.

        Returns
        -------
        InitializeEventFP
            The converted fixed point InitializeEventFP object.
        """

        return InitializeEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=InitializeEventFP.InitializeEventArgsFP(
                provider=in_val.args.provider,
                lp_amount=FixedPoint(scaled_value=in_val.args.lpAmount),
                amount=FixedPoint(scaled_value=in_val.args.amount),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                as_base=in_val.args.asBase,
                apr=FixedPoint(scaled_value=in_val.args.apr),
                extra_data=in_val.args.extraData,
            ),
        )

    def to_pypechain(self) -> InitializeEvent:
        """Convert a fixed point InitializeEventFP object to a pypechain InitializeEvent object.

        Returns
        -------
        InitializeEvent
            The converted pypechain InitializeEvent object.
        """

        return InitializeEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=InitializeEvent.InitializeEventArgs(
                provider=self.args.provider,
                lpAmount=self.args.lp_amount.scaled_value,
                amount=self.args.amount.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                asBase=self.args.as_base,
                apr=self.args.apr.scaled_value,
                extraData=self.args.extra_data,
            ),
        )


@dataclass(kw_only=True)
class OpenLongEventFP(OpenLongEvent):
    """OpenLongEvent event."""

    @dataclass(kw_only=True)
    class OpenLongEventArgsFP(BaseEventArgs):
        """The args to the event OpenLongEvent"""

        trader: str
        asset_id: int
        maturity_time: int
        amount: FixedPoint
        vault_share_price: FixedPoint
        as_base: bool
        bond_amount: FixedPoint
        extra_data: bytes

    # We redefine the type in the subclass
    args: OpenLongEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: OpenLongEvent) -> OpenLongEventFP:
        """Convert a pypechain OpenLongEvent object to a fixed point OpenLongEventFP object.

        Arguments
        ---------
        in_val: OpenLongEvent
            The pypechain OpenLongEvent object to convert.

        Returns
        -------
        OpenLongEventFP
            The converted fixed point OpenLongEventFP object.
        """

        return OpenLongEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=OpenLongEventFP.OpenLongEventArgsFP(
                trader=in_val.args.trader,
                asset_id=in_val.args.assetId,
                maturity_time=in_val.args.maturityTime,
                amount=FixedPoint(scaled_value=in_val.args.amount),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                as_base=in_val.args.asBase,
                bond_amount=FixedPoint(scaled_value=in_val.args.bondAmount),
                extra_data=in_val.args.extraData,
            ),
        )

    def to_pypechain(self) -> OpenLongEvent:
        """Convert a fixed point OpenLongEventFP object to a pypechain OpenLongEvent object.

        Returns
        -------
        OpenLongEvent
            The converted pypechain OpenLongEvent object.
        """

        return OpenLongEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=OpenLongEvent.OpenLongEventArgs(
                trader=self.args.trader,
                assetId=self.args.asset_id,
                maturityTime=self.args.maturity_time,
                amount=self.args.amount.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                asBase=self.args.as_base,
                bondAmount=self.args.bond_amount.scaled_value,
                extraData=self.args.extra_data,
            ),
        )


@dataclass(kw_only=True)
class OpenShortEventFP(OpenShortEvent):
    """OpenShortEvent event."""

    @dataclass(kw_only=True)
    class OpenShortEventArgsFP(BaseEventArgs):
        """The args to the event OpenShortEvent"""

        trader: str
        asset_id: int
        maturity_time: int
        amount: FixedPoint
        vault_share_price: FixedPoint
        as_base: bool
        base_proceeds: FixedPoint
        bond_amount: FixedPoint
        extra_data: bytes

    # We redefine the type in the subclass
    args: OpenShortEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: OpenShortEvent) -> OpenShortEventFP:
        """Convert a pypechain OpenShortEvent object to a fixed point OpenShortEventFP object.

        Arguments
        ---------
        in_val: OpenShortEvent
            The pypechain OpenShortEvent object to convert.

        Returns
        -------
        OpenShortEventFP
            The converted fixed point OpenShortEventFP object.
        """

        return OpenShortEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=OpenShortEventFP.OpenShortEventArgsFP(
                trader=in_val.args.trader,
                asset_id=in_val.args.assetId,
                maturity_time=in_val.args.maturityTime,
                amount=FixedPoint(scaled_value=in_val.args.amount),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                as_base=in_val.args.asBase,
                base_proceeds=FixedPoint(scaled_value=in_val.args.baseProceeds),
                bond_amount=FixedPoint(scaled_value=in_val.args.bondAmount),
                extra_data=in_val.args.extraData,
            ),
        )

    def to_pypechain(self) -> OpenShortEvent:
        """Convert a fixed point OpenShortEventFP object to a pypechain OpenShortEvent object.

        Returns
        -------
        OpenShortEvent
            The converted pypechain OpenShortEvent object.
        """

        return OpenShortEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=OpenShortEvent.OpenShortEventArgs(
                trader=self.args.trader,
                assetId=self.args.asset_id,
                maturityTime=self.args.maturity_time,
                amount=self.args.amount.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                asBase=self.args.as_base,
                baseProceeds=self.args.base_proceeds.scaled_value,
                bondAmount=self.args.bond_amount.scaled_value,
                extraData=self.args.extra_data,
            ),
        )


@dataclass(kw_only=True)
class RedeemWithdrawalSharesEventFP(RedeemWithdrawalSharesEvent):
    """RedeemWithdrawalSharesEvent event."""

    @dataclass(kw_only=True)
    class RedeemWithdrawalSharesEventArgsFP(BaseEventArgs):
        """The args to the event RedeemWithdrawalSharesEvent"""

        provider: str
        destination: str
        withdrawal_share_amount: FixedPoint
        amount: FixedPoint
        vault_share_price: FixedPoint
        as_base: bool
        extra_data: bytes

    # We redefine the type in the subclass
    args: RedeemWithdrawalSharesEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: RedeemWithdrawalSharesEvent) -> RedeemWithdrawalSharesEventFP:
        """Convert a pypechain RedeemWithdrawalSharesEvent object to a fixed point RedeemWithdrawalSharesEventFP object.

        Arguments
        ---------
        in_val: RedeemWithdrawalSharesEvent
            The pypechain RedeemWithdrawalSharesEvent object to convert.

        Returns
        -------
        RedeemWithdrawalSharesEventFP
            The converted fixed point RedeemWithdrawalSharesEventFP object.
        """

        return RedeemWithdrawalSharesEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=RedeemWithdrawalSharesEventFP.RedeemWithdrawalSharesEventArgsFP(
                provider=in_val.args.provider,
                destination=in_val.args.destination,
                withdrawal_share_amount=FixedPoint(scaled_value=in_val.args.withdrawalShareAmount),
                amount=FixedPoint(scaled_value=in_val.args.amount),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                as_base=in_val.args.asBase,
                extra_data=in_val.args.extraData,
            ),
        )

    def to_pypechain(self) -> RedeemWithdrawalSharesEvent:
        """Convert a fixed point RedeemWithdrawalSharesEventFP object to a pypechain RedeemWithdrawalSharesEvent object.

        Returns
        -------
        RedeemWithdrawalSharesEvent
            The converted pypechain RedeemWithdrawalSharesEvent object.
        """

        return RedeemWithdrawalSharesEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=RedeemWithdrawalSharesEvent.RedeemWithdrawalSharesEventArgs(
                provider=self.args.provider,
                destination=self.args.destination,
                withdrawalShareAmount=self.args.withdrawal_share_amount.scaled_value,
                amount=self.args.amount.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                asBase=self.args.as_base,
                extraData=self.args.extra_data,
            ),
        )


@dataclass(kw_only=True)
class RemoveLiquidityEventFP(RemoveLiquidityEvent):
    """RemoveLiquidity event."""

    @dataclass(kw_only=True)
    class RemoveLiquidityEventArgsFP(BaseEventArgs):
        """The args to the event RemoveLiquidityEvent"""

        provider: str
        destination: str
        lp_amount: FixedPoint
        amount: FixedPoint
        vault_share_price: FixedPoint
        as_base: bool
        withdrawal_share_amount: FixedPoint
        lp_share_price: FixedPoint
        extra_data: bytes

    # We redefine the type in the subclass
    args: RemoveLiquidityEventArgsFP  # type: ignore[override]

    @classmethod
    def from_pypechain(cls, in_val: RemoveLiquidityEvent) -> RemoveLiquidityEventFP:
        """Convert a pypechain RemoveLiquidityEvent object to a fixed point RemoveLiquidityEventFP object.

        Arguments
        ---------
        in_val: RemoveLiquidityEvent
            The pypechain RemoveLiquidityEvent object to convert.

        Returns
        -------
        RemoveLiquidityEventFP
            The converted fixed point RemoveLiquidityEventFP object.
        """

        return RemoveLiquidityEventFP(
            log_index=in_val.log_index,
            transaction_index=in_val.transaction_index,
            transaction_hash=in_val.transaction_hash,
            address=in_val.address,
            block_hash=in_val.block_hash,
            block_number=in_val.block_number,
            args=RemoveLiquidityEventFP.RemoveLiquidityEventArgsFP(
                provider=in_val.args.provider,
                destination=in_val.args.destination,
                lp_amount=FixedPoint(scaled_value=in_val.args.lpAmount),
                amount=FixedPoint(scaled_value=in_val.args.amount),
                vault_share_price=FixedPoint(scaled_value=in_val.args.vaultSharePrice),
                as_base=in_val.args.asBase,
                withdrawal_share_amount=FixedPoint(scaled_value=in_val.args.withdrawalShareAmount),
                lp_share_price=FixedPoint(scaled_value=in_val.args.lpSharePrice),
                extra_data=in_val.args.extraData,
            ),
        )

    def to_pypechain(self) -> RemoveLiquidityEvent:
        """Convert a fixed point RemoveLiquidityEventFP object to a pypechain RemoveLiquidityEvent object.

        Returns
        -------
        RemoveLiquidityEvent
            The converted pypechain RemoveLiquidityEvent object.
        """

        return RemoveLiquidityEvent(
            log_index=self.log_index,
            transaction_index=self.transaction_index,
            transaction_hash=self.transaction_hash,
            address=self.address,
            block_hash=self.block_hash,
            block_number=self.block_number,
            args=RemoveLiquidityEvent.RemoveLiquidityEventArgs(
                provider=self.args.provider,
                destination=self.args.destination,
                lpAmount=self.args.lp_amount.scaled_value,
                amount=self.args.amount.scaled_value,
                vaultSharePrice=self.args.vault_share_price.scaled_value,
                asBase=self.args.as_base,
                withdrawalShareAmount=self.args.withdrawal_share_amount.scaled_value,
                lpSharePrice=self.args.lp_share_price.scaled_value,
                extraData=self.args.extra_data,
            ),
        )
