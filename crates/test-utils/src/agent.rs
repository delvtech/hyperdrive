use crate::hyperdrive::Hyperdrive;
use ethers::{
    prelude::EthLogDecode,
    types::{Address, U256},
};
use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::uint256;
use hyperdrive_wrappers::wrappers::i_hyperdrive::IHyperdriveEvents;
use std::collections::BTreeMap;
use std::fmt;

#[derive(Default)]
struct Wallet {
    base: FixedPoint,
    lp_shares: FixedPoint,
    withdrawal_shares: FixedPoint,
    longs: BTreeMap<FixedPoint, FixedPoint>,
    shorts: BTreeMap<FixedPoint, FixedPoint>,
}

pub struct Agent {
    address: Address,
    hyperdrive: Hyperdrive,
    wallet: Wallet,
}

impl fmt::Debug for Agent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Agent")
            .field("address", &self.address)
            .field("base", &self.wallet.base)
            .field("lp_shares", &self.wallet.lp_shares)
            .field("withdrawal_shares", &self.wallet.withdrawal_shares)
            .field("longs", &self.wallet.longs)
            .field("shorts", &self.wallet.shorts)
            .finish()
    }
}

// FIXME: There should be a cleaner way of creating the agent than this.
//
// TODO: This has the barebones logic required for integration and fuzz tests;
// however, we'll need the max trade calculations to be able to fuzz with sane
// trade limits.
impl Agent {
    pub fn new(hyperdrive: Hyperdrive, address: Address) -> Self {
        Self {
            address,
            hyperdrive,
            wallet: Wallet::default(),
        }
    }

    pub async fn fund(&mut self, amount: FixedPoint) -> Result<()> {
        // Mint some base tokens.
        self.hyperdrive
            .base
            .mint(amount.into())
            .from(self.address)
            .send()
            .await?;

        // Approve hyperdrive to spend the base tokens.
        self.hyperdrive
            .base
            .approve(self.hyperdrive.hyperdrive.address(), amount.into())
            .from(self.address)
            .send()
            .await?;

        // Increase the base balance in the wallet.
        self.wallet.base += amount;

        Ok(())
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

    // TODO: There should be reasonable limits on this. If we set a reasonable
    // max deposit, then this would be simple.
    pub async fn open_short(&mut self, bond_amount: FixedPoint) -> Result<()> {
        // Open the short and record the trade in the wallet.
        let log = {
            let tx = self
                .hyperdrive
                .hyperdrive
                .open_short(bond_amount.into(), bond_amount.into(), self.address, true)
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
            logs[0].clone()
        };
        self.wallet.base += log.base_amount.into();
        self.wallet.withdrawal_shares -= log.withdrawal_share_amount.into();

        Ok(())
    }

    /// Getters ///

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
}
