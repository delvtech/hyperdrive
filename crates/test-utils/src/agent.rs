use std::{cmp::min, collections::BTreeMap, fmt, sync::Arc};

use ethers::{
    middleware::SignerMiddleware,
    prelude::EthLogDecode,
    providers::{Http, Middleware, Provider},
    signers::LocalWallet,
    types::{Address, U256},
};
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::{fixed, uint256};
use hyperdrive_addresses::Addresses;
use hyperdrive_math::hyperdrive_math::State;
use hyperdrive_wrappers::wrappers::{
    erc20_mintable::ERC20Mintable,
    erc4626_data_provider::ERC4626DataProvider,
    i_hyperdrive::{Checkpoint, IHyperdrive, IHyperdriveEvents, PoolConfig},
    mock_erc4626::MockERC4626,
};
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;
use tracing::{info, instrument};

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

// TODO: This agent could be more RPC efficient.
//
/// An agent that interacts with the Hyperdrive protocol and records its
/// balances of longs, shorts, base, and lp shares (both active and withdrawal
/// shares).
pub struct Agent<M, R>
where
    R: Rng + SeedableRng,
{
    address: Address,
    provider: Provider<Http>,
    hyperdrive: IHyperdrive<M>,
    pool: MockERC4626<M>,
    base: ERC20Mintable<M>,
    config: PoolConfig,
    wallet: Wallet,
    rng: R,
    seed: u64,
}

impl<M, R> fmt::Debug for Agent<M, R>
where
    R: Rng + SeedableRng,
{
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

// TODO: This should crash gracefully and would ideally dump the replication
// information to a file that can be read by the framework to easily debug what
// happened.
impl Agent<SignerMiddleware<Provider<Http>, LocalWallet>, ChaCha8Rng> {
    /// Setup ///

    pub async fn new(
        client: Arc<SignerMiddleware<Provider<Http>, LocalWallet>>,
        addresses: Addresses,
        maybe_seed: Option<u64>,
    ) -> Result<Self> {
        let seed = maybe_seed.unwrap_or(17);
        let pool = ERC4626DataProvider::new(addresses.hyperdrive, client.clone())
            .pool()
            .call()
            .await?;
        let pool = MockERC4626::new(pool, client.clone());
        let hyperdrive = IHyperdrive::new(addresses.hyperdrive, client.clone());
        Ok(Self {
            address: client.address(),
            provider: client.provider().clone(),
            hyperdrive: hyperdrive.clone(),
            pool,
            base: ERC20Mintable::new(addresses.base, client),
            config: hyperdrive.get_pool_config().call().await?,
            wallet: Wallet::default(),
            rng: ChaCha8Rng::seed_from_u64(seed),
            seed,
        })
    }

    /// Longs ///

    pub async fn open_long(&mut self, base_paid: FixedPoint) -> Result<()> {
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
            let tx = self
                .hyperdrive
                .open_long(base_paid.into(), base_paid.into(), self.address, true)
                .from(self.address);
            let logs = tx
                .send()
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

    pub async fn close_long(
        &mut self,
        maturity_time: FixedPoint,
        bond_amount: FixedPoint,
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
            let tx = self
                .hyperdrive
                .close_long(
                    maturity_time.into(),
                    bond_amount.into(),
                    uint256!(0),
                    self.address,
                    true,
                )
                .from(self.address);
            let logs = tx
                .send()
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

    pub async fn open_short(
        &mut self,
        bond_amount: FixedPoint,
        maybe_slippage_tolerance: Option<FixedPoint>,
    ) -> Result<()> {
        // Open the short and record the trade in the wallet.
        let log = {
            let slippage_tolerance = maybe_slippage_tolerance.unwrap_or(fixed!(0.01e18));
            let min_output =
                self.get_short_deposit(bond_amount).await? * (fixed!(1e18) + slippage_tolerance);
            let tx = self
                .hyperdrive
                .open_short(bond_amount.into(), min_output.into(), self.address, true)
                .from(self.address);
            let logs = tx
                .send()
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

    pub async fn close_short(
        &mut self,
        maturity_time: FixedPoint,
        bond_amount: FixedPoint,
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
            let tx = self
                .hyperdrive
                .close_short(
                    maturity_time.into(),
                    bond_amount.into(),
                    uint256!(0),
                    self.address,
                    true,
                )
                .from(self.address);
            let logs = tx
                .send()
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

    pub async fn initialize(&mut self, rate: FixedPoint, contribution: FixedPoint) -> Result<()> {
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
            let tx = self
                .hyperdrive
                .initialize(contribution.into(), rate.into(), self.address, true)
                .from(self.address);
            let logs = tx
                .send()
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

    pub async fn add_liquidity(&mut self, contribution: FixedPoint) -> Result<()> {
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
            let tx = self
                .hyperdrive
                .add_liquidity(
                    contribution.into(),
                    uint256!(0),
                    U256::MAX,
                    self.address,
                    true,
                )
                .from(self.address);
            let logs = tx
                .send()
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

    pub async fn remove_liquidity(&mut self, shares: FixedPoint) -> Result<()> {
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
            let tx = self
                .hyperdrive
                .remove_liquidity(shares.into(), uint256!(0), self.address, true)
                .from(self.address);
            let logs = tx
                .send()
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

    pub async fn redeem_withdrawal_shares(&mut self, shares: FixedPoint) -> Result<()> {
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
            let tx = self
                .hyperdrive
                .redeem_withdrawal_shares(shares.into(), uint256!(0), self.address, true)
                .from(self.address);
            let logs = tx
                .send()
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
            logs.get(0).cloned()
        };
        if let Some(log) = log {
            self.wallet.base += log.base_amount.into();
            self.wallet.withdrawal_shares -= log.withdrawal_share_amount.into();
        }

        Ok(())
    }

    /// Checkpoint ///

    pub async fn checkpoint(&mut self, checkpoint: U256) -> Result<()> {
        self.hyperdrive.checkpoint(checkpoint).send().await?;
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
        let max_long_base = self.get_max_long(None).await?;
        let max_short_bonds = self.get_max_short().await?;
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
        if self.wallet.longs.len() > 0 {
            let maturity_time = self
                .wallet
                .longs
                .keys()
                .nth(self.rng.gen_range(0..self.wallet.longs.keys().len()))
                .unwrap()
                .clone();
            actions.push(Action::CloseLong(
                maturity_time,
                self.rng
                    .gen_range(fixed!(1e8)..=self.wallet.longs[&maturity_time]),
            ));
        }
        if self.wallet.shorts.len() > 0 {
            let maturity_time = self
                .wallet
                .shorts
                .keys()
                .nth(self.rng.gen_range(0..self.wallet.shorts.keys().len()))
                .unwrap()
                .clone();
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
            Action::AddLiquidity(contribution) => self.add_liquidity(contribution).await?,
            Action::RemoveLiquidity(lp_shares) => self.remove_liquidity(lp_shares).await?,
            Action::RedeemWithdrawalShares(withdrawal_shares) => {
                self.redeem_withdrawal_shares(withdrawal_shares).await?
            }
            Action::OpenLong(base_paid) => self.open_long(base_paid).await?,
            Action::CloseLong(maturity_time, bond_amount) => {
                self.close_long(maturity_time, bond_amount).await?
            }
            Action::OpenShort(bond_amount) => self.open_short(bond_amount, None).await?,
            Action::CloseShort(maturity_time, bond_amount) => {
                self.close_short(maturity_time, bond_amount).await?
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

    pub async fn advance_time(&self, rate: FixedPoint, duration: FixedPoint) -> Result<()> {
        self.pool.set_rate(rate.into()).send().await?;
        self.provider
            .request::<[U256; 1], u64>("evm_increaseTime", [duration.into()])
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

    /// Gets the deposit required to short a given amount of bonds with the
    /// current market state.
    pub async fn get_short_deposit(&self, short_amount: FixedPoint) -> Result<FixedPoint> {
        let state = self.get_state().await?;
        let Checkpoint {
            share_price: open_share_price,
            ..
        } = self
            .hyperdrive
            .get_checkpoint(state.to_checkpoint(self.now().await?))
            .await?;
        println!("short_amount: {}", short_amount);
        println!("open_share_price: {}", open_share_price);
        Ok(state.get_short_deposit(
            short_amount,
            state.get_spot_price(),
            open_share_price.into(),
        ))
    }

    /// Gets the max long that can be opened in the current checkpoint.
    pub async fn get_max_long(&self, maybe_max_iterations: Option<usize>) -> Result<FixedPoint> {
        let state = self.get_state().await?;
        Ok(state.get_max_long(self.wallet.base, maybe_max_iterations))
    }

    /// Gets the max short that can be opened in the current checkpoint.
    pub async fn get_max_short(&self) -> Result<FixedPoint> {
        let state = self.get_state().await?;
        let Checkpoint {
            share_price: open_share_price,
            ..
        } = self
            .hyperdrive
            .get_checkpoint(state.to_checkpoint(self.now().await?))
            .await?;

        // We linearly interpolate between the current spot price and the minimum
        // price that the pool can support. This is a conservative estimate of
        // the short's realized price.
        let conservative_price = {
            // We estimate the minimum price that short will pay by a
            // weighted average of the spot price and the minimum possible
            // spot price the pool can quote. We choose the weights so that this
            // is an underestimate of the worst case realized price.
            let spot_price = state.get_spot_price();
            let min_price = state.get_min_price();

            // Calculate the linear interpolation.
            let base_reserves = FixedPoint::from(state.info.share_price)
                * (FixedPoint::from(state.info.share_reserves));
            let weight = (min(self.wallet.base, base_reserves) / base_reserves)
                .pow(fixed!(1e18) - FixedPoint::from(self.config.time_stretch));
            spot_price * (fixed!(1e18) - weight) + min_price * weight
        };

        Ok(state.get_max_short(
            self.wallet.base,
            open_share_price.into(),
            Some(conservative_price),
            None,
        ))
    }

    // TODO: We'll need to implement helpers that give us the maximum trade
    // for an older checkpoint. We'll need to use these when closig trades.
}
