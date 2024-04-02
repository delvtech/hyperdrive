use std::{cmp::min, collections::BTreeMap, fmt, sync::Arc, time::Duration};

use ethers::{
    abi::Detokenize,
    contract::ContractCall,
    prelude::EthLogDecode,
    providers::{Http, Middleware, Provider, RetryClient},
    types::{Address, BlockId, I256, U256},
};
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_addresses::Addresses;
use hyperdrive_math::State;
use hyperdrive_wrappers::wrappers::{
    erc20_mintable::ERC20Mintable,
    ihyperdrive::{Checkpoint, IHyperdrive, IHyperdriveEvents, Options, PoolConfig},
    mock_erc4626::MockERC4626,
};
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use tokio::time::sleep;
use tracing::{info, instrument};

use super::chain::ChainClient;

#[derive(Copy, Clone, Debug)]
enum Action {
    Noop,
    AddLiquidity(FixedPoint),
    RemoveLiquidity(FixedPoint),
    RedeemWithdrawalShares(FixedPoint),
    OpenLong(FixedPoint),
    CloseLong(FixedPoint, FixedPoint),
    OpenShort(FixedPoint),
    CloseShort(FixedPoint, FixedPoint),
}

#[derive(Default)]
pub struct Wallet {
    base: FixedPoint,
    lp_shares: FixedPoint,
    withdrawal_shares: FixedPoint,
    longs: BTreeMap<FixedPoint, FixedPoint>,
    shorts: BTreeMap<FixedPoint, FixedPoint>,
}

/// An agent that interacts with the Hyperdrive protocol and records its
/// balances of longs, shorts, base, and lp shares (both active and withdrawal
/// shares).
pub struct Agent<M, R: Rng + SeedableRng> {
    address: Address,
    provider: Provider<Arc<RetryClient<Http>>>,
    hyperdrive: IHyperdrive<M>,
    vault: MockERC4626<M>,
    base: ERC20Mintable<M>,
    config: PoolConfig,
    wallet: Wallet,
    // TODO: It would probably be better to store an Arc<R> here so that all of
    // the agents reference the same Rng.
    rng: R,
    seed: u64,
}

impl<M, R: Rng + SeedableRng> fmt::Debug for Agent<M, R> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Agent")
            .field("address", &self.address)
            .field("seed", &self.seed)
            .field("base", &self.wallet.base)
            .field("lp_shares", &self.wallet.lp_shares)
            .field("withdrawal_shares", &self.wallet.withdrawal_shares)
            .field("longs", &self.wallet.longs)
            .field("shorts", &self.wallet.shorts)
            .finish()
    }
}

#[derive(Clone, Default, Debug)]
pub struct TxOptions {
    from: Option<Address>,
    gas: Option<U256>,
    gas_price: Option<U256>,
    value: Option<U256>,
    block: Option<BlockId>,
    is_legacy: bool,
}

impl TxOptions {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn from(mut self, from: Address) -> Self {
        self.from = Some(from);
        self
    }

    pub fn gas(mut self, gas: U256) -> Self {
        self.gas = Some(gas);
        self
    }

    pub fn gas_price(mut self, gas_price: U256) -> Self {
        self.gas_price = Some(gas_price);
        self
    }

    pub fn value(mut self, value: U256) -> Self {
        self.value = Some(value);
        self
    }

    pub fn block(mut self, block: BlockId) -> Self {
        self.block = Some(block);
        self
    }

    pub fn legacy(mut self) -> Self {
        self.is_legacy = true;
        self
    }
}

/// A helper struct that makes it easy to apply transaction options to a
/// contract call.
struct ContractCall_<M, D>(ContractCall<M, D>);

impl<M, D: Detokenize> ContractCall_<M, D> {
    fn apply(self, tx_options: TxOptions) -> Self {
        let mut call = self.0;
        if let Some(from) = tx_options.from {
            call = call.from(from);
        }
        if let Some(gas) = tx_options.gas {
            call = call.gas(gas);
        }
        if let Some(gas_price) = tx_options.gas_price {
            call = call.gas_price(gas_price);
        }
        if let Some(value) = tx_options.value {
            call = call.value(value);
        }
        if let Some(block) = tx_options.block {
            call = call.block(block);
        }
        if tx_options.is_legacy {
            call = call.legacy();
        }

        ContractCall_(call)
    }
}

// TODO: This should crash gracefully and would ideally dump the replication
// information to a file that can be read by the framework to easily debug what
// happened.
impl Agent<ChainClient, ChaCha8Rng> {
    /// Setup ///

    pub async fn new(
        client: Arc<ChainClient>,
        addresses: Addresses,
        maybe_seed: Option<u64>,
    ) -> Result<Self> {
        let seed = maybe_seed.unwrap_or(17);
        let vault = IHyperdrive::new(addresses.erc4626_hyperdrive, client.clone())
            .vault_shares_token()
            .call()
            .await?;
        let vault = MockERC4626::new(vault, client.clone());
        // TODO: Eventually, the agent should be able to support several
        // different pools simultaneously.
        let hyperdrive = IHyperdrive::new(addresses.erc4626_hyperdrive, client.clone());
        Ok(Self {
            address: client.address(),
            provider: client.provider().clone(),
            hyperdrive: hyperdrive.clone(),
            vault,
            base: ERC20Mintable::new(addresses.base_token, client),
            config: hyperdrive.get_pool_config().call().await?,
            wallet: Wallet::default(),
            rng: ChaCha8Rng::seed_from_u64(seed),
            seed,
        })
    }

    /// Longs ///

    #[instrument(skip(self))]
    pub async fn open_long(
        &mut self,
        base_paid: FixedPoint,
        maybe_slippage_tolerance: Option<FixedPoint>,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // Ensure that the agent has a sufficient base balance to open the long.
        if self.wallet.base < base_paid {
            return Err(eyre::eyre!(
                "insufficient base balance to open long: {:?} < {:?}",
                self.wallet.base,
                base_paid
            ));
        }

        // Decrease the wallet's base balance.
        self.wallet.base -= base_paid;

        // Open the long and record the trade in the wallet.
        let log = {
            let min_output = {
                let slippage_tolerance = maybe_slippage_tolerance.unwrap_or(fixed!(0.01e18));
                self.calculate_open_long(base_paid).await? * (fixed!(1e18) - slippage_tolerance)
            };
            let tx = ContractCall_(self.hyperdrive.open_long(
                base_paid.into(),
                min_output.into(),
                fixed!(0).into(), // TODO: This is fine for testing, but not prod.
                Options {
                    destination: self.address,
                    as_base: true,
                    extra_data: [].into(),
                },
            ))
            .apply(self.pre_process_options(maybe_tx_options));
            let logs =
                tx.0.send()
                    .await?
                    .await?
                    .unwrap()
                    .logs
                    .into_iter()
                    .filter_map(|log| {
                        if let Ok(IHyperdriveEvents::OpenLongFilter(log)) =
                            IHyperdriveEvents::decode_log(&log.into())
                        {
                            Some(log)
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
            logs[0].clone()
        };
        *self
            .wallet
            .longs
            .entry(log.maturity_time.into())
            .or_default() += log.bond_amount.into();

        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn close_long(
        &mut self,
        maturity_time: FixedPoint,
        bond_amount: FixedPoint,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // TODO: It would probably be better for this part of the agent to just
        // be a dumb wrapper around Hyperdrive. It's going to be useful to test
        // with inputs that we'd consider invalid.
        //
        // If the wallet has a sufficient balance of longs, update the long
        // balance. Otherwise, return an error.
        let long_balance = self.wallet.longs.entry(maturity_time).or_default();
        if *long_balance > bond_amount {
            *long_balance -= bond_amount;
        } else if *long_balance == bond_amount {
            self.wallet.longs.remove(&maturity_time);
        } else {
            return Err(eyre::eyre!(
                "insufficient long balance to close long: {:?} < {:?}",
                long_balance,
                bond_amount
            ));
        }

        // Close the long and increase the wallet's base balance.
        let log = {
            let tx = ContractCall_(self.hyperdrive.close_long(
                maturity_time.into(),
                bond_amount.into(),
                uint256!(0),
                Options {
                    destination: self.address,
                    as_base: true,
                    extra_data: [].into(),
                },
            ))
            .apply(self.pre_process_options(maybe_tx_options));
            let logs =
                tx.0.send()
                    .await?
                    .await?
                    .unwrap()
                    .logs
                    .into_iter()
                    .filter_map(|log| {
                        if let Ok(IHyperdriveEvents::CloseLongFilter(log)) =
                            IHyperdriveEvents::decode_log(&log.into())
                        {
                            Some(log)
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
            logs[0].clone()
        };
        self.wallet.base += log.base_amount.into();

        Ok(())
    }

    /// Shorts ///

    #[instrument(skip(self))]
    pub async fn open_short(
        &mut self,
        bond_amount: FixedPoint,
        maybe_slippage_tolerance: Option<FixedPoint>,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // Open the short and record the trade in the wallet.
        let log = {
            let max_deposit = {
                let slippage_tolerance = maybe_slippage_tolerance.unwrap_or(fixed!(0.01e18));
                self.calculate_open_short(bond_amount).await? * (fixed!(1e18) + slippage_tolerance)
            };
            let tx = ContractCall_(self.hyperdrive.open_short(
                bond_amount.into(),
                max_deposit.into(),
                fixed!(0).into(), // TODO: This is fine for testing, but not prod.
                Options {
                    destination: self.address,
                    as_base: true,
                    extra_data: [].into(),
                },
            ))
            .apply(self.pre_process_options(maybe_tx_options));
            let logs =
                tx.0.send()
                    .await?
                    .await?
                    .unwrap()
                    .logs
                    .into_iter()
                    .filter_map(|log| {
                        if let Ok(IHyperdriveEvents::OpenShortFilter(log)) =
                            IHyperdriveEvents::decode_log(&log.into())
                        {
                            Some(log)
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
            logs[0].clone()
        };
        *self
            .wallet
            .shorts
            .entry(log.maturity_time.into())
            .or_default() += log.bond_amount.into();

        // Decrease the wallet's base balance.
        self.wallet.base -= log.base_amount.into();

        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn close_short(
        &mut self,
        maturity_time: FixedPoint,
        bond_amount: FixedPoint,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // If the wallet has a sufficient balance of shorts, update the short
        // balance. Otherwise, return an error.
        let short_balance = self.wallet.shorts.entry(maturity_time).or_default();
        if *short_balance > bond_amount {
            *short_balance -= bond_amount;
        } else if *short_balance == bond_amount {
            self.wallet.shorts.remove(&maturity_time);
        } else {
            return Err(eyre::eyre!(
                "insufficient short balance to close short: {:?} < {:?}",
                short_balance,
                bond_amount
            ));
        }

        // Close the long and increase the wallet's base balance.
        let log = {
            let tx = ContractCall_(self.hyperdrive.close_short(
                maturity_time.into(),
                bond_amount.into(),
                uint256!(0),
                Options {
                    destination: self.address,
                    as_base: true,
                    extra_data: [].into(),
                },
            ))
            .apply(self.pre_process_options(maybe_tx_options));
            let logs =
                tx.0.send()
                    .await?
                    .await?
                    .unwrap()
                    .logs
                    .into_iter()
                    .filter_map(|log| {
                        if let Ok(IHyperdriveEvents::CloseShortFilter(log)) =
                            IHyperdriveEvents::decode_log(&log.into())
                        {
                            Some(log)
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
            logs[0].clone()
        };
        self.wallet.base += log.base_amount.into();

        Ok(())
    }

    /// LPs ///

    #[instrument(skip(self))]
    pub async fn initialize(
        &mut self,
        rate: FixedPoint,
        contribution: FixedPoint,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // Ensure that the agent has a sufficient base balance to initialize the pool.
        if self.wallet.base < contribution {
            return Err(eyre::eyre!(
                "insufficient base balance to initialize: {:?} < {:?}",
                self.wallet.base,
                contribution
            ));
        }
        self.wallet.base -= contribution;

        // Initialize the pool and record the LP shares that were received in the wallet.
        let log = {
            let tx = ContractCall_(self.hyperdrive.initialize(
                contribution.into(),
                rate.into(),
                Options {
                    destination: self.address,
                    as_base: true,
                    extra_data: [].into(),
                },
            ))
            .apply(self.pre_process_options(maybe_tx_options));
            let logs =
                tx.0.send()
                    .await?
                    .await?
                    .unwrap()
                    .logs
                    .into_iter()
                    .filter_map(|log| {
                        if let Ok(IHyperdriveEvents::InitializeFilter(log)) =
                            IHyperdriveEvents::decode_log(&log.into())
                        {
                            Some(log)
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
            logs[0].clone()
        };
        self.wallet.lp_shares = log.lp_amount.into();

        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn add_liquidity(
        &mut self,
        contribution: FixedPoint,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // Ensure that the agent has a sufficient base balance to add liquidity.
        if self.wallet.base < contribution {
            return Err(eyre::eyre!(
                "insufficient base balance to add liquidity: {:?} < {:?}",
                self.wallet.base,
                contribution
            ));
        }
        self.wallet.base -= contribution;

        // Add liquidity and record the LP shares that were received in the wallet.
        let log = {
            let tx = ContractCall_(self.hyperdrive.add_liquidity(
                contribution.into(),
                uint256!(0),
                uint256!(0),
                U256::MAX,
                Options {
                    destination: self.address,
                    as_base: true,
                    extra_data: [].into(),
                },
            ))
            .apply(self.pre_process_options(maybe_tx_options));
            let logs =
                tx.0.send()
                    .await?
                    .await?
                    .unwrap()
                    .logs
                    .into_iter()
                    .filter_map(|log| {
                        if let Ok(IHyperdriveEvents::AddLiquidityFilter(log)) =
                            IHyperdriveEvents::decode_log(&log.into())
                        {
                            Some(log)
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
            logs[0].clone()
        };
        self.wallet.lp_shares += log.lp_amount.into();

        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn remove_liquidity(
        &mut self,
        shares: FixedPoint,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // Ensure that the agent has a sufficient balance of LP shares.
        if self.wallet.lp_shares < shares {
            return Err(eyre::eyre!(
                "insufficient LP share balance to remove liquidity: {:?} < {:?}",
                self.wallet.lp_shares,
                shares
            ));
        }

        // Decrease the wallet's LP share balance.
        self.wallet.lp_shares -= shares;

        // Remove liquidity and record the base and withdrawal shares that were
        // received.
        let log = {
            let tx = ContractCall_(self.hyperdrive.remove_liquidity(
                shares.into(),
                uint256!(0),
                Options {
                    destination: self.address,
                    as_base: true,
                    extra_data: [].into(),
                },
            ))
            .apply(self.pre_process_options(maybe_tx_options));
            let logs =
                tx.0.send()
                    .await?
                    .await?
                    .unwrap()
                    .logs
                    .into_iter()
                    .filter_map(|log| {
                        if let Ok(IHyperdriveEvents::RemoveLiquidityFilter(log)) =
                            IHyperdriveEvents::decode_log(&log.into())
                        {
                            Some(log)
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
            logs[0].clone()
        };
        self.wallet.base += log.base_amount.into();
        self.wallet.withdrawal_shares += log.withdrawal_share_amount.into();

        Ok(())
    }

    #[instrument(skip(self))]
    pub async fn redeem_withdrawal_shares(
        &mut self,
        shares: FixedPoint,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // Ensure that the agent has a sufficient balance of withdrawal shares.
        if self.wallet.withdrawal_shares < shares {
            return Err(eyre::eyre!(
                "insufficient withdrawal share balance to redeem withdrawal shares: {:?} < {:?}",
                self.wallet.withdrawal_shares,
                shares
            ));
        }

        // Redeem the withdrawal shares and record the base and withdrawal
        // shares that were redeemed.
        let log = {
            let tx = ContractCall_(self.hyperdrive.redeem_withdrawal_shares(
                shares.into(),
                uint256!(0),
                Options {
                    destination: self.address,
                    as_base: true,
                    extra_data: [].into(),
                },
            ))
            .apply(self.pre_process_options(maybe_tx_options));
            let logs =
                tx.0.send()
                    .await?
                    .await?
                    .unwrap()
                    .logs
                    .into_iter()
                    .filter_map(|log| {
                        if let Ok(IHyperdriveEvents::RedeemWithdrawalSharesFilter(log)) =
                            IHyperdriveEvents::decode_log(&log.into())
                        {
                            Some(log)
                        } else {
                            None
                        }
                    })
                    .collect::<Vec<_>>();
            logs.first().cloned()
        };
        if let Some(log) = log {
            self.wallet.base += log.base_amount.into();
            self.wallet.withdrawal_shares -= log.withdrawal_share_amount.into();
        }

        Ok(())
    }

    /// Checkpoint ///

    #[instrument(skip(self))]
    pub async fn checkpoint(
        &self,
        checkpoint: U256,
        max_iterations: U256,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        let tx = ContractCall_(self.hyperdrive.checkpoint(checkpoint, max_iterations))
            .apply(self.pre_process_options(maybe_tx_options));
        tx.0.send().await?.await?;
        Ok(())
    }

    /// Test Utils ///

    /// Executes a random action.
    #[instrument(skip(self))]
    pub async fn act(&mut self) -> Result<()> {
        let action = self.sample_action().await?;
        info!("executing an action: {:?}", action);
        self.execute_action(action).await
    }

    /// Samples a random action from the action space.
    async fn sample_action(&mut self) -> Result<Action> {
        // Randomly generate a list of actions to sample over.
        let mut actions = vec![Action::Noop];
        if self.wallet.base > fixed!(0) {
            actions.push(Action::AddLiquidity(
                self.rng.gen_range(fixed!(1)..=self.wallet.base),
            ));
        }
        if self.wallet.lp_shares > fixed!(0) {
            actions.push(Action::RemoveLiquidity(
                self.rng.gen_range(fixed!(1)..=self.wallet.lp_shares),
            ));
        }
        if self.wallet.withdrawal_shares > fixed!(0) {
            actions.push(Action::RedeemWithdrawalShares(
                self.rng
                    .gen_range(fixed!(1)..=self.wallet.withdrawal_shares),
            ));
        }
        let max_long_base = self.calculate_max_long(None).await?;
        let max_short_bonds = self.calculate_max_short(None).await?;
        if max_long_base >= fixed!(1e18) {
            actions
                .push(Action::OpenLong(self.rng.gen_range(
                    fixed!(1e18)..=min(max_long_base, self.wallet.base),
                )));
        }
        // TODO: Remove this limitation.
        if max_short_bonds >= fixed!(1e18) {
            actions.push(Action::OpenShort(
                self.rng.gen_range(fixed!(1)..=max_short_bonds),
            ));
        }
        if !self.wallet.longs.is_empty() {
            let maturity_time = *self
                .wallet
                .longs
                .keys()
                .nth(self.rng.gen_range(0..self.wallet.longs.keys().len()))
                .unwrap();
            actions.push(Action::CloseLong(
                maturity_time,
                self.rng
                    .gen_range(fixed!(1e8)..=self.wallet.longs[&maturity_time]),
            ));
        }
        if !self.wallet.shorts.is_empty() {
            let maturity_time = *self
                .wallet
                .shorts
                .keys()
                .nth(self.rng.gen_range(0..self.wallet.shorts.keys().len()))
                .unwrap();
            actions.push(Action::CloseShort(
                maturity_time,
                self.rng
                    .gen_range(fixed!(1e8)..=self.wallet.shorts[&maturity_time]),
            ));
        }

        // Sample one of the actions.
        Ok(actions[self.rng.gen_range(0..actions.len())])
    }

    /// Executes an actions. This makes some testing workflows easier because
    /// the tester just needs to generate an array of actions rather than having
    /// a bespoke sampler that calls functions.
    async fn execute_action(&mut self, action: Action) -> Result<()> {
        match action {
            Action::Noop => (),
            Action::AddLiquidity(contribution) => self.add_liquidity(contribution, None).await?,
            Action::RemoveLiquidity(lp_shares) => self.remove_liquidity(lp_shares, None).await?,
            Action::RedeemWithdrawalShares(withdrawal_shares) => {
                self.redeem_withdrawal_shares(withdrawal_shares, None)
                    .await?
            }
            Action::OpenLong(base_paid) => self.open_long(base_paid, None, None).await?,
            Action::CloseLong(maturity_time, bond_amount) => {
                self.close_long(maturity_time, bond_amount, None).await?
            }
            Action::OpenShort(bond_amount) => self.open_short(bond_amount, None, None).await?,
            Action::CloseShort(maturity_time, bond_amount) => {
                self.close_short(maturity_time, bond_amount, None).await?
            }
        }

        Ok(())
    }

    /// Funds the wallet with some base tokens and sets the approval on the
    /// Hyperdrive contract.
    pub async fn fund(&mut self, amount: FixedPoint) -> Result<()> {
        // Mint some base tokens.
        self.base
            .mint(amount.into())
            .from(self.address)
            .send()
            .await?;

        // HACK: Sleep for a few ms to give anvil some time to catch up. We
        // shouldn't need this, but anvil gets stuck in timeout loops when
        // these calls are made in quick succession with retries.
        sleep(Duration::from_millis(50)).await;

        // Approve hyperdrive to spend the base tokens.
        self.base
            .approve(self.hyperdrive.address(), amount.into())
            .from(self.address)
            .send()
            .await?;

        // Increase the base balance in the wallet.
        self.wallet.base += amount;

        Ok(())
    }

    /// Advances the chain's time and changes the pool's variable rate so that
    /// interest accrues.
    pub async fn advance_time(&self, rate: FixedPoint, duration: FixedPoint) -> Result<()> {
        // Set the new variable rate.
        self.vault.set_rate(rate.into()).send().await?;

        // Advance the chain's time and mine a block. Mining a block is
        // important because client's check the current block time by looking
        // at the latest block's timestamp.
        self.provider
            .request::<[u128; 1], i128>("anvil_increaseTime", [duration.into()])
            .await?;
        self.provider
            .request::<[u128; 1], ()>("anvil_mine", [1])
            .await?;

        Ok(())
    }

    /// Advances the chain's time and changes the pool's variable rate so that
    /// interest accrues. This function advances time in increments of the
    /// checkpoint duration and mints every checkpoint that is passed over.
    pub async fn advance_time_with_checkpoints(
        &self,
        rate: FixedPoint,
        mut duration: FixedPoint,
        maybe_tx_options: Option<TxOptions>,
    ) -> Result<()> {
        // Set the new variable rate.
        self.vault.set_rate(rate.into()).send().await?;

        // Advance time one checkpoint at a time until we've advanced time by
        // the full duration.
        let checkpoint_duration = self.get_config().checkpoint_duration.into();
        while duration > checkpoint_duration {
            // Advance the chain's time by the checkpoint duration and mint a
            // new checkpoint.
            self.provider
                .request::<[U256; 1], u64>("evm_increaseTime", [checkpoint_duration.into()])
                .await?;
            self.provider
                .request::<_, U256>("evm_mine", None::<()>)
                .await?;
            self.checkpoint(
                self.latest_checkpoint().await?,
                uint256!(0),
                maybe_tx_options.clone(),
            )
            .await?;
            duration -= checkpoint_duration;
        }

        // Advance the chain's time by the remaining duration and mint a new
        // checkpoint.
        self.provider
            .request::<[U256; 1], u64>("evm_increaseTime", [duration.into()])
            .await?;
        self.provider
            .request::<_, U256>("evm_mine", None::<()>)
            .await?;
        self.checkpoint(
            self.latest_checkpoint().await?,
            uint256!(0),
            maybe_tx_options,
        )
        .await?;

        Ok(())
    }

    /// Resets the agent's wallet.
    ///
    /// This is useful for testing because it makes it easy to use the agent
    /// across multiple snapshots.
    pub fn reset(&mut self, wallet: Wallet) {
        self.wallet = wallet;
    }

    /// Getters ///

    pub fn address(&self) -> Address {
        self.address
    }

    // TODO: It may be better to group these into a single getter that returns
    // the agent's wallet.
    pub fn base(&self) -> FixedPoint {
        self.wallet.base
    }

    pub fn lp_shares(&self) -> FixedPoint {
        self.wallet.lp_shares
    }

    pub fn withdrawal_shares(&self) -> FixedPoint {
        self.wallet.withdrawal_shares
    }

    pub fn longs(&self) -> &BTreeMap<FixedPoint, FixedPoint> {
        &self.wallet.longs
    }

    pub fn shorts(&self) -> &BTreeMap<FixedPoint, FixedPoint> {
        &self.wallet.shorts
    }

    /// Gets the current timestamp.
    pub async fn now(&self) -> Result<U256> {
        Ok(self
            .provider
            .get_block(self.provider.get_block_number().await?)
            .await?
            .unwrap()
            .timestamp)
    }

    /// Gets the latest checkpoint.
    pub async fn latest_checkpoint(&self) -> Result<U256> {
        Ok(self.get_state().await?.to_checkpoint(self.now().await?))
    }

    /// Gets the pool config.
    pub fn get_config(&self) -> &PoolConfig {
        &self.config
    }

    /// Gets the current state of the pool.
    pub async fn get_state(&self) -> Result<State> {
        Ok(State::new(
            self.config.clone(),
            self.hyperdrive.get_pool_info().await?,
        ))
    }

    /// Gets a checkpoint.
    pub async fn get_checkpoint(&self, id: U256) -> Result<Checkpoint> {
        Ok(self.hyperdrive.get_checkpoint(id).await?)
    }

    /// Gets the checkpoint exposure.
    pub async fn get_checkpoint_exposure(&self, id: U256) -> Result<I256> {
        Ok(self.hyperdrive.get_checkpoint_exposure(id).await?)
    }

    /// Calculates the spot price.
    pub async fn calculate_spot_price(&self) -> Result<FixedPoint> {
        Ok(self.get_state().await?.calculate_spot_price())
    }

    /// Calculates the amount of longs that will be opened for a given amount of base
    /// with the current market state.
    pub async fn calculate_open_long(&self, base_amount: FixedPoint) -> Result<FixedPoint> {
        let state = self.get_state().await?;
        Ok(state.calculate_open_long(base_amount))
    }

    /// Calculates the deposit required to short a given amount of bonds with the
    /// current market state.
    pub async fn calculate_open_short(&self, short_amount: FixedPoint) -> Result<FixedPoint> {
        let state = self.get_state().await?;
        let Checkpoint {
            vault_share_price: open_vault_share_price,
            ..
        } = self
            .hyperdrive
            .get_checkpoint(state.to_checkpoint(self.now().await?))
            .await?;
        state.calculate_open_short(
            short_amount,
            state.calculate_spot_price(),
            open_vault_share_price.into(),
        )
    }

    /// Calculates the max long that can be opened in the current checkpoint.
    pub async fn calculate_max_long(
        &self,
        maybe_max_iterations: Option<usize>,
    ) -> Result<FixedPoint> {
        let state = self.get_state().await?;
        let checkpoint_exposure = self
            .hyperdrive
            .get_checkpoint_exposure(state.to_checkpoint(self.now().await?))
            .await?;
        Ok(state.calculate_max_long(self.wallet.base, checkpoint_exposure, maybe_max_iterations))
    }

    /// Calculates the max short that can be opened in the current checkpoint.
    ///
    /// Since interest can accrue between the time the calculation is made and
    /// the transaction is submitted, it's convenient to have a slippage
    /// tolerance to lower the revert rate.
    pub async fn calculate_max_short(
        &self,
        maybe_slippage_tolerance: Option<FixedPoint>,
    ) -> Result<FixedPoint> {
        let budget =
            self.wallet.base * (fixed!(1e18) - maybe_slippage_tolerance.unwrap_or(fixed!(0.01e18)));

        let state = self.get_state().await?;
        let Checkpoint {
            vault_share_price: open_vault_share_price,
            ..
        } = self
            .hyperdrive
            .get_checkpoint(state.to_checkpoint(self.now().await?))
            .await?;
        let checkpoint_exposure = self
            .hyperdrive
            .get_checkpoint_exposure(state.to_checkpoint(self.now().await?))
            .await?;

        // We linearly interpolate between the current spot price and the minimum
        // price that the pool can support. This is a conservative estimate of
        // the short's realized price.
        let conservative_price = {
            // We estimate the minimum price that short will pay by a
            // weighted average of the spot price and the minimum possible
            // spot price the pool can quote. We choose the weights so that this
            // is an underestimate of the worst case realized price.
            let spot_price = state.calculate_spot_price();
            let min_price = state.calculate_min_price();

            // Calculate the linear interpolation.
            let base_reserves = FixedPoint::from(state.info.vault_share_price)
                * (FixedPoint::from(state.info.share_reserves));
            let weight = (min(self.wallet.base, base_reserves) / base_reserves)
                .pow(fixed!(1e18) - FixedPoint::from(self.config.time_stretch));
            spot_price * (fixed!(1e18) - weight) + min_price * weight
        };

        Ok(state.calculate_max_short(
            budget,
            open_vault_share_price,
            checkpoint_exposure,
            Some(conservative_price),
            None,
        ))
    }

    // TODO: We'll need to implement helpers that give us the maximum trade
    // for an older checkpoint. We'll need to use these when closig trades.

    /// Helpers ///

    fn pre_process_options(&self, maybe_tx_options: Option<TxOptions>) -> TxOptions {
        maybe_tx_options
            .map(|mut tx_options| {
                if tx_options.from.is_none() {
                    tx_options.from = Some(self.address);
                }
                tx_options
            })
            .unwrap_or_default()
    }
}
