/// This module provides the `CrashReport` struct which implents `Deserialize`.
/// It is intended to be used to deserialize crash reports from JSON.
use ethers::types::{Address, Bytes, H256, U256};
use hyperdrive_addresses::Addresses;
use hyperdrive_wrappers::wrappers::i_hyperdrive::{Checkpoint, Fees, PoolConfig, PoolInfo};
use serde::{Deserialize, Deserializer};

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
pub struct AgentInfo {
    pub address: Address,
    pub policy: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ActionType {
    // LP Actions
    Initialize,
    AddLiquidity,
    RemoveLiquidity,
    #[serde(alias = "REDEEM_WITHDRAW_SHARE")]
    RedeemWithdrawalShares,
    // Long
    OpenLong,
    CloseLong,
    // Short
    OpenShort,
    CloseShort,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Trade {
    pub market_type: String,
    pub action_type: ActionType,
    pub trade_amount: U256,
    pub slippage_tolerance: Option<U256>,
    pub maturity_time: u64,
}

#[derive(Deserialize)]
struct RawTrade {
    market_type: String,
    action_type: ActionType,
    trade_amount: u128,
    slippage_tolerance: Option<u128>,
    maturity_time: u64,
}

impl From<RawTrade> for Trade {
    fn from(r: RawTrade) -> Self {
        Self {
            market_type: r.market_type,
            action_type: r.action_type,
            trade_amount: U256::from(r.trade_amount),
            slippage_tolerance: r.slippage_tolerance.map(U256::from),
            maturity_time: r.maturity_time,
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawPoolConfig {
    base_token: Address,
    linker_factory: Address,
    linker_code_hash: H256,
    initial_share_price: u128,
    minimum_share_reserves: u128,
    minimum_transaction_amount: u128,
    position_duration: u64,
    checkpoint_duration: u64,
    time_stretch: u128,
    governance: Address,
    fee_collector: Address,
    fees: Vec<u128>,
}

impl From<RawPoolConfig> for PoolConfig {
    fn from(r: RawPoolConfig) -> Self {
        if r.fees.len() != 3 {
            panic!("Expected 3 fees, got {}", r.fees.len());
        }
        Self {
            base_token: r.base_token,
            linker_factory: r.linker_factory,
            linker_code_hash: r.linker_code_hash.into(),
            initial_share_price: r.initial_share_price.into(),
            minimum_share_reserves: r.minimum_share_reserves.into(),
            minimum_transaction_amount: r.minimum_transaction_amount.into(),
            position_duration: r.position_duration.into(),
            checkpoint_duration: r.checkpoint_duration.into(),
            time_stretch: r.time_stretch.into(),
            governance: r.governance,
            fee_collector: r.fee_collector,
            fees: Fees {
                curve: r.fees[0].into(),
                flat: r.fees[1].into(),
                governance: r.fees[2].into(),
            },
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawPoolInfo {
    share_reserves: u128,
    share_adjustment: i128,
    bond_reserves: u128,
    lp_total_supply: u128,
    share_price: u128,
    longs_outstanding: u128,
    long_average_maturity_time: u128,
    shorts_outstanding: u128,
    short_average_maturity_time: u128,
    withdrawal_shares_ready_to_withdraw: u128,
    withdrawal_shares_proceeds: u128,
    lp_share_price: u128,
    long_exposure: u128,
}

impl From<RawPoolInfo> for PoolInfo {
    fn from(r: RawPoolInfo) -> Self {
        Self {
            share_reserves: r.share_reserves.into(),
            share_adjustment: r.share_adjustment.into(),
            bond_reserves: r.bond_reserves.into(),
            lp_total_supply: r.lp_total_supply.into(),
            share_price: r.share_price.into(),
            longs_outstanding: r.longs_outstanding.into(),
            long_average_maturity_time: r.long_average_maturity_time.into(),
            shorts_outstanding: r.shorts_outstanding.into(),
            short_average_maturity_time: r.short_average_maturity_time.into(),
            withdrawal_shares_ready_to_withdraw: r.withdrawal_shares_ready_to_withdraw.into(),
            withdrawal_shares_proceeds: r.withdrawal_shares_proceeds.into(),
            lp_share_price: r.lp_share_price.into(),
            long_exposure: r.long_exposure.into(),
        }
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawCheckpoint {
    share_price: u128,
    long_exposure: i128,
}

impl From<RawCheckpoint> for Checkpoint {
    fn from(r: RawCheckpoint) -> Self {
        Self {
            share_price: r.share_price.into(),
            long_exposure: r.long_exposure.into(),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CrashReport {
    /// Crash Metadata
    pub commit_hash: String,
    pub log_time: String,
    pub exception: String,
    pub traceback: Vec<String>,
    /// Block Metadata
    pub block_number: u64,
    pub block_timestamp: u64,
    /// Agent Context
    pub addresses: Addresses,
    pub agent_info: AgentInfo,
    pub trade: Trade,
    /// Pool Context
    pub pool_config: PoolConfig,
    pub pool_info: PoolInfo,
    pub checkpoint: Checkpoint,
    /// State Dump
    pub state_dump: Bytes,
}

#[derive(Deserialize)]
struct RawCrashReport {
    // Crash Metadata
    commit_hash: String,
    log_time: String,
    exception: String,
    traceback: Vec<String>,
    // Block Metadata
    block_number: u64,
    block_timestamp: u64,
    // Agent Context
    #[serde(rename = "contract_addresses")]
    addresses: Addresses,
    agent_info: AgentInfo,
    #[serde(rename = "raw_trade_object")]
    trade: RawTrade,
    // Pool Context
    #[serde(rename = "raw_pool_config")]
    pool_config: RawPoolConfig,
    #[serde(rename = "raw_pool_info")]
    pool_info: RawPoolInfo,
    #[serde(rename = "raw_checkpoint")]
    checkpoint: RawCheckpoint,
    // State Dump
    #[serde(rename = "anvil_dump_state")]
    state_dump: Bytes,
}

impl From<RawCrashReport> for CrashReport {
    fn from(r: RawCrashReport) -> Self {
        Self {
            // Crash Metadata
            commit_hash: r.commit_hash,
            log_time: r.log_time,
            exception: r.exception,
            traceback: r.traceback,
            // Block Metadata
            block_number: r.block_number,
            block_timestamp: r.block_timestamp,
            // Agent Context
            addresses: r.addresses,
            agent_info: r.agent_info.into(),
            trade: r.trade.into(),
            // Pool Context
            pool_config: r.pool_config.into(),
            pool_info: r.pool_info.into(),
            checkpoint: r.checkpoint.into(),
            // State Dump
            state_dump: r.state_dump,
        }
    }
}

impl<'de> Deserialize<'de> for CrashReport {
    fn deserialize<D>(deserializer: D) -> Result<CrashReport, D::Error>
    where
        D: Deserializer<'de>,
    {
        Ok(RawCrashReport::deserialize(deserializer)?.into())
    }
}

#[cfg(test)]
mod tests {
    use eyre::Result;
    use fixed_point_macros::{int256, uint256};
    use hyperdrive_wrappers::wrappers::i_hyperdrive::Fees;

    use super::*;

    #[test]
    fn test_decode_crash_report() -> Result<()> {
        let raw_crash_report = r#"{
    "commit_hash": "3e50df86672f436e3645daadcffbb925381dc166",
    "log_time": "2023-10-20T21:28:21.521190+00:00",
    "exception": "AssertionError('Invalid balance: REDEEM_WITHDRAW_SHARE for 99999999999.0 withdraw shares, balance of 0.0 withdraw shares.', 'Transaction receipt had no logs', \"tx_receipt=AttributeDict({'transactionHash': HexBytes('0x28c505127565c429c5ed222b22d5d5ec18ed6c20b5caba8facb4cf568e77c435'), 'transactionIndex': 0, 'blockHash': HexBytes('0x4be26d1186182c4a6f71b6aefd37a3b3df8eaf5fb7e0ad7c6ed3abc084730abc'), 'blockNumber': 16, 'from': '0x31b86D1eC3DB7f34656B5308DD94C6a29a0226D8', 'to': '0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81', 'cumulativeGasUsed': 77042, 'gasUsed': 77042, 'contractAddress': None, 'logs': [], 'status': 1, 'logsBloom': HexBytes('0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'), 'type': 2, 'effectiveGasPrice': 1501690774})\", 'Call previewed in block 15')",
    "traceback": [
        "  File \"/Users/slundquist/workspace/elf-simulations/lib/agent0/agent0/hyperdrive/exec/execute_agent_trades.py\", line 250, in async_match_contract_call_to_trade\n    trade_result = await hyperdrive.async_redeem_withdraw_shares(agent, trade.trade_amount, nonce=nonce)\n",
        "  File \"/Users/slundquist/workspace/elf-simulations/lib/ethpy/ethpy/hyperdrive/api.py\", line 928, in async_redeem_withdraw_shares\n    raise exc\n",
        "  File \"/Users/slundquist/workspace/elf-simulations/lib/ethpy/ethpy/hyperdrive/api.py\", line 924, in async_redeem_withdraw_shares\n    trade_result = parse_logs(tx_receipt, self.hyperdrive_contract, \"redeemWithdrawalShares\")\n",
        "  File \"/Users/slundquist/workspace/elf-simulations/lib/ethpy/ethpy/hyperdrive/interface.py\", line 240, in parse_logs\n    raise AssertionError(\"Transaction receipt had no logs\", f\"{tx_receipt=}\")\n"
    ],
    "block_number": 16,
    "block_timestamp": 1697837314,
    "agent_info": {
        "address": "0x31b86D1eC3DB7f34656B5308DD94C6a29a0226D8",
        "policy": "MultiTradePolicy"
    },
    "contract_addresses": {
        "hyperdrive_address": "0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81",
        "base_token_address": "0x5FbDB2315678afecb367f032d93F642f64180aa3"
    },
    "raw_trade_object": {
        "market_type": "HYPERDRIVE",
        "action_type": "REDEEM_WITHDRAW_SHARE",
        "trade_amount": 1000000000000000000,
        "slippage_tolerance": null,
        "maturity_time": 604800
    },
    "raw_pool_config": {
        "baseToken": "0x5FbDB2315678afecb367f032d93F642f64180aa3",
        "linkerFactory": "0x33027547537D35728a741470dF1CCf65dE10b454",
        "linkerCodeHash": "0x33027547537d35728a741470df1ccf65de10b454ca0def7c5c20b257b7b8d161",
        "initialSharePrice": 1000000000000000000,
        "minimumShareReserves": 10000000000000000000,
        "minimumTransactionAmount": 1000000000000000,
        "positionDuration": 604800,
        "checkpointDuration": 3600,
        "timeStretch": 44463125629060298,
        "governance": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "feeCollector": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "fees": [
            100000000000000000,
            500000000000000,
            150000000000000000
        ]
    },
    "raw_pool_info": {
        "shareReserves": 100000000000000000000000000,
        "shareAdjustment": 0,
        "bondReserves": 102178995195337961200000000,
        "lpTotalSupply": 99999990000000000000000000,
        "sharePrice": 1000000006341958396,
        "longsOutstanding": 0,
        "longAverageMaturityTime": 0,
        "shortsOutstanding": 0,
        "shortAverageMaturityTime": 0,
        "withdrawalSharesReadyToWithdraw": 0,
        "withdrawalSharesProceeds": 0,
        "lpSharePrice": 1000000006341958396,
        "longExposure": 0
    },
    "raw_checkpoint": {
        "sharePrice": 1000000000000000000,
        "longExposure": 0
    },
    "anvil_dump_state": "0x7b22",
    "additional_info": {
        "spot_price": "0.999032273280673843",
        "fixed_rate": "0.050508914905668004",
        "variable_rate": "0.05",
        "vault_shares": "100033384.563972725414955382"
    },
    "trade": {
        "market_type": "HYPERDRIVE",
        "action_type": "REDEEM_WITHDRAW_SHARE",
        "trade_amount": "99999999999.0",
        "slippage_tolerance": null,
        "maturity_time": 604800
    },
    "wallet": {
        "base": "966615.435727223931266024",
        "longs": [
            {
                "maturity_time": 1698440400,
                "balance": "22240.960380161547270613"
            }
        ],
        "shorts": [
            {
                "maturity_time": 1698440400,
                "balance": "33333.0"
            }
        ],
        "lp_tokens": "11110.999911918126025819",
        "withdraw_shares": "0.0"
    },
    "pool_config": {
        "baseToken": "0x5FbDB2315678afecb367f032d93F642f64180aa3",
        "linkerFactory": "0x33027547537D35728a741470dF1CCf65dE10b454",
        "linkerCodeHash": "0x33027547537d35728a741470df1ccf65de10b454ca0def7c5c20b257b7b8d161",
        "initialSharePrice": "1.0",
        "minimumShareReserves": "10.0",
        "minimumTransactionAmount": "0.001",
        "positionDuration": 604800,
        "checkpointDuration": 3600,
        "timeStretch": "0.044463125629060298",
        "governance": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "feeCollector": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        "fees": [
            "0.1",
            "0.0005",
            "0.15"
        ],
        "contractAddress": "0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81",
        "curveFee": "0.1",
        "flatFee": "0.0005",
        "governanceFee": "0.15",
        "invTimeStretch": "22.490546623794212364"
    },
    "pool_info": {
        "shareReserves": "100000000.0",
        "shareAdjustment": "0.0",
        "bondReserves": "102178995.1953379612",
        "lpTotalSupply": "99999990.0",
        "sharePrice": "1.000000006341958396",
        "longsOutstanding": "0.0",
        "longAverageMaturityTime": "0.0",
        "shortsOutstanding": "0.0",
        "shortAverageMaturityTime": "0.0",
        "withdrawalSharesReadyToWithdraw": "0.0",
        "withdrawalSharesProceeds": "0.0",
        "lpSharePrice": "1.000000006341958396",
        "longExposure": "0.0",
        "timestamp": "2023-10-20 21:28:34",
        "blockNumber": 16,
        "totalSupplyWithdrawalShares": 0
    },
    "checkpoint_info": {
        "sharePrice": "1.0",
        "longExposure": "0.0",
        "blockNumber": 16,
        "timestamp": "2023-10-20 14:28:34"
    }
        }"#;
        assert_eq!(
            serde_json::from_str::<CrashReport>(raw_crash_report)?,
            CrashReport {
                // Crash Metadata
                commit_hash: "3e50df86672f436e3645daadcffbb925381dc166".to_string(),
                log_time: "2023-10-20T21:28:21.521190+00:00".to_string(),
                exception: "AssertionError('Invalid balance: REDEEM_WITHDRAW_SHARE for 99999999999.0 withdraw shares, balance of 0.0 withdraw shares.', 'Transaction receipt had no logs', \"tx_receipt=AttributeDict({'transactionHash': HexBytes('0x28c505127565c429c5ed222b22d5d5ec18ed6c20b5caba8facb4cf568e77c435'), 'transactionIndex': 0, 'blockHash': HexBytes('0x4be26d1186182c4a6f71b6aefd37a3b3df8eaf5fb7e0ad7c6ed3abc084730abc'), 'blockNumber': 16, 'from': '0x31b86D1eC3DB7f34656B5308DD94C6a29a0226D8', 'to': '0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81', 'cumulativeGasUsed': 77042, 'gasUsed': 77042, 'contractAddress': None, 'logs': [], 'status': 1, 'logsBloom': HexBytes('0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000'), 'type': 2, 'effectiveGasPrice': 1501690774})\", 'Call previewed in block 15')".to_string(),
                traceback: vec![
                    "  File \"/Users/slundquist/workspace/elf-simulations/lib/agent0/agent0/hyperdrive/exec/execute_agent_trades.py\", line 250, in async_match_contract_call_to_trade\n    trade_result = await hyperdrive.async_redeem_withdraw_shares(agent, trade.trade_amount, nonce=nonce)\n",
                    "  File \"/Users/slundquist/workspace/elf-simulations/lib/ethpy/ethpy/hyperdrive/api.py\", line 928, in async_redeem_withdraw_shares\n    raise exc\n",
                    "  File \"/Users/slundquist/workspace/elf-simulations/lib/ethpy/ethpy/hyperdrive/api.py\", line 924, in async_redeem_withdraw_shares\n    trade_result = parse_logs(tx_receipt, self.hyperdrive_contract, \"redeemWithdrawalShares\")\n",
                    "  File \"/Users/slundquist/workspace/elf-simulations/lib/ethpy/ethpy/hyperdrive/interface.py\", line 240, in parse_logs\n    raise AssertionError(\"Transaction receipt had no logs\", f\"{tx_receipt=}\")\n"
                ].into_iter().map(|s| s.to_string()).collect(),
                // Block Metadata
                block_number: 16,
                block_timestamp: 1697837314,
                // Agent Context
                addresses: Addresses {
                    base: "0x5FbDB2315678afecb367f032d93F642f64180aa3".parse()?,
                    hyperdrive: "0xd8058efe0198ae9dD7D563e1b4938Dcbc86A1F81".parse()?,
                },
                agent_info: AgentInfo {
                    address: "0x31b86D1eC3DB7f34656B5308DD94C6a29a0226D8".parse()?,
                    policy: "MultiTradePolicy".to_string(),
                },
                trade: Trade {
                    market_type: "HYPERDRIVE".to_string(),
                    action_type: ActionType::RedeemWithdrawalShares,
                    trade_amount: uint256!(1000000000000000000),
                    slippage_tolerance: None,
                    maturity_time: 604800
                },
                // Pool Context
                pool_config: PoolConfig {
                    base_token: "0x5FbDB2315678afecb367f032d93F642f64180aa3".parse()?,
                    linker_factory: "0x33027547537D35728a741470dF1CCf65dE10b454".parse()?,
                    linker_code_hash: "0x33027547537d35728a741470df1ccf65de10b454ca0def7c5c20b257b7b8d161".parse::<H256>()?.into(),
                    initial_share_price: uint256!(1000000000000000000),
                    minimum_share_reserves: uint256!(10000000000000000000),
                    minimum_transaction_amount: uint256!(1000000000000000),
                    position_duration: uint256!(604800),
                    checkpoint_duration: uint256!(3600),
                    time_stretch: uint256!(44463125629060298),
                    governance: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266".parse()?,
                    fee_collector: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266".parse()?,
                    fees: Fees {
                        curve: uint256!(100000000000000000),
                        flat: uint256!(500000000000000),
                        governance: uint256!(150000000000000000),
                    },
                },
                pool_info: PoolInfo {
                    share_reserves: uint256!(100000000000000000000000000),
                    share_adjustment: int256!(0),
                    bond_reserves: uint256!(102178995195337961200000000),
                    lp_total_supply: uint256!(99999990000000000000000000),
                    share_price: uint256!(1000000006341958396),
                    longs_outstanding: uint256!(0),
                    long_average_maturity_time: uint256!(0),
                    shorts_outstanding: uint256!(0),
                    short_average_maturity_time: uint256!(0),
                    withdrawal_shares_ready_to_withdraw: uint256!(0),
                    withdrawal_shares_proceeds: uint256!(0),
                    lp_share_price: uint256!(1000000006341958396),
                    long_exposure: uint256!(0)
                },
                checkpoint: Checkpoint {
                    share_price: 1000000000000000000,
                    long_exposure: 0,
                },
                // State Dump
                state_dump: "0x7b22".parse()?,
            },
        );

        Ok(())
    }
}
