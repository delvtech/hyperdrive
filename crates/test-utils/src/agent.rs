use crate::{generated::ihyperdrive::IHyperdriveEvents, hyperdrive::Hyperdrive};
use ethers::{
    prelude::EthLogDecode,
    types::{Address, U256},
};
use eyre::Result;
use std::collections::BTreeMap;

#[derive(Default)]
struct Wallet {
    base: U256,
    lp_shares: U256,
    withdrawal_shares: U256,
    longs: BTreeMap<U256, U256>,
    shorts: BTreeMap<U256, U256>,
}

pub struct Agent {
    address: Address,
    hyperdrive: Hyperdrive,
    wallet: Wallet,
}

// TODO: This has the barebones logic required for integration and fuzz tests;
// however, we'll need the max trade calculations to be able to fuzz with sane
// trade limits.
impl Agent {
    pub fn new(hyperdrive: Hyperdrive, address: Address) -> Self {
        Self {
            address,
            hyperdrive,
            wallet: Wallet {
                base: U256::zero(),
                lp_shares: U256::zero(),
                withdrawal_shares: U256::zero(),
                longs: BTreeMap::new(),
                shorts: BTreeMap::new(),
            },
        }
    }

    pub async fn fund(&mut self, amount: U256) -> Result<()> {
        // Mint some base tokens.
        self.hyperdrive
            .base
            .mint(amount)
            .from(self.address)
            .send()
            .await?;

        // Approve hyperdrive to spend the base tokens.
        self.hyperdrive
            .base
            .approve(self.hyperdrive.hyperdrive.address(), amount)
            .from(self.address)
            .send()
            .await?;

        // Increase the base balance in the wallet.
        self.wallet.base += amount;

        Ok(())
    }

    /// Longs ///

    pub async fn open_long(&mut self, base_paid: U256) -> Result<()> {
        // Ensure that the agent has a sufficient base balance to open the long.
        if self.wallet.base < base_paid {
            return Err(eyre::eyre!(
                "insufficient base balance to open long: {} < {}",
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
                .open_long(base_paid, base_paid, self.address, true)
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
        *self.wallet.longs.entry(log.maturity_time).or_default() += log.bond_amount;

        Ok(())
    }

    pub async fn close_long(&mut self, maturity_time: U256, bond_amount: U256) -> Result<()> {
        // If the wallet has a sufficient balance of longs, update the long
        // balance. Otherwise, return an error.
        let long_balance = self.wallet.longs.entry(maturity_time).or_default();
        if *long_balance < bond_amount {
            return Err(eyre::eyre!(
                "insufficient long balance to close long: {} < {}",
                long_balance,
                bond_amount
            ));
        }
        *long_balance -= bond_amount;

        // Close the long and increase the wallet's base balance.
        let log = {
            let tx = self
                .hyperdrive
                .hyperdrive
                .close_long(maturity_time, bond_amount, U256::zero(), self.address, true)
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
        self.wallet.base += log.base_amount;

        Ok(())
    }

    /// Shorts ///

    // TODO: There should be reasonable limits on this. If we set a reasonable
    // max deposit, then this would be simple.
    pub async fn open_short(&mut self, bond_amount: U256) -> Result<()> {
        // Open the short and record the trade in the wallet.
        let log = {
            let tx = self
                .hyperdrive
                .hyperdrive
                .open_short(bond_amount, bond_amount, self.address, true)
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
        *self.wallet.shorts.entry(log.maturity_time).or_default() += log.bond_amount;

        // Decrease the wallet's base balance.
        self.wallet.base -= log.base_amount;

        Ok(())
    }

    pub async fn close_short(&mut self, maturity_time: U256, bond_amount: U256) -> Result<()> {
        // If the wallet has a sufficient balance of shorts, update the short
        // balance. Otherwise, return an error.
        let short_balance = self.wallet.shorts.entry(maturity_time).or_default();
        if *short_balance < bond_amount {
            return Err(eyre::eyre!(
                "insufficient short balance to close short: {} < {}",
                short_balance,
                bond_amount
            ));
        }
        *short_balance -= bond_amount;

        // Close the long and increase the wallet's base balance.
        let log = {
            let tx = self
                .hyperdrive
                .hyperdrive
                .close_short(maturity_time, bond_amount, U256::zero(), self.address, true)
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
        self.wallet.base += log.base_amount;

        Ok(())
    }

    /// LPs ///

    pub async fn add_liquidity(&mut self, contribution: U256) -> Result<()> {
        // Ensure that the agent has a sufficient base balance to add liquidity.
        if self.wallet.base < contribution {
            return Err(eyre::eyre!(
                "insufficient base balance to add liquidity: {} < {}",
                self.wallet.base,
                contribution
            ));
        }

        // Decrease the wallet's base balance.
        self.wallet.base -= contribution;

        // Add liquidity and record the LP shares that were received in the wallet.
        let log = {
            let tx = self
                .hyperdrive
                .hyperdrive
                .add_liquidity(contribution, U256::zero(), U256::MAX, self.address, true)
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
        self.wallet.lp_shares += log.lp_amount;

        Ok(())
    }

    pub async fn remove_liquidity(&mut self, shares: U256) -> Result<()> {
        // Ensure that the agent has a sufficient balance of LP shares.
        if self.wallet.lp_shares < shares {
            return Err(eyre::eyre!(
                "insufficient LP share balance to remove liquidity: {} < {}",
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
                .remove_liquidity(shares, U256::zero(), self.address, true)
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
        self.wallet.base += log.base_amount;
        self.wallet.withdrawal_shares += log.withdrawal_share_amount;

        Ok(())
    }

    pub async fn redeem_withdrawal_shares(&mut self, shares: U256) -> Result<()> {
        // Ensure that the agent has a sufficient balance of withdrawal shares.
        if self.wallet.withdrawal_shares < shares {
            return Err(eyre::eyre!(
                "insufficient withdrawal share balance to redeem withdrawal shares: {} < {}",
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
                .redeem_withdrawal_shares(shares, U256::zero(), self.address, true)
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
        self.wallet.base += log.base_amount;
        self.wallet.withdrawal_shares -= log.withdrawal_share_amount;

        Ok(())
    }
}
