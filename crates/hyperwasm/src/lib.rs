use ethers::core::types::{Address, I256, U256};
use fixed_point::FixedPoint;
use hyperdrive_math::hyperdrive_math::State;
use hyperdrive_wrappers::wrappers::i_hyperdrive::{Fees, PoolConfig, PoolInfo};
use serde::{Deserialize, Serialize};
use wasm_bindgen::prelude::*;

#[wasm_bindgen]
pub fn get_max_long(
    state: JsValue,
    budget: &str,
    checkpoint_exposure: &str,
    max_iterations: Option<usize>,
) -> Result<JsValue, JsValue> {
    let wasm_state: WasmState = serde_wasm_bindgen::from_value(state)?;
    let state = State::from(&wasm_state);

    let max = state.get_max_long::<FixedPoint, I256>(
        FixedPoint::from(U256::from_dec_str(budget).unwrap()),
        I256::from_dec_str(checkpoint_exposure).unwrap(),
        max_iterations,
    );

    Ok(max.to_string().into())
}

#[derive(Serialize, Deserialize)]
pub struct WasmFees {
    pub curve: U256,
    pub flat: U256,
    pub governance: U256,
}

#[derive(Serialize, Deserialize)]
pub struct WasmPoolConfig {
    pub base_token: Address,
    pub initial_share_price: U256,
    pub minimum_share_reserves: U256,
    pub minimum_transaction_amount: U256,
    pub position_duration: U256,
    pub checkpoint_duration: U256,
    pub time_stretch: U256,
    pub governance: Address,
    pub fee_collector: Address,
    pub fees: WasmFees,
    pub oracle_size: U256,
    pub update_gap: U256,
}

#[derive(Serialize, Deserialize)]
pub struct WasmPoolInfo {
    pub share_reserves: U256,
    pub bond_reserves: U256,
    pub lp_total_supply: U256,
    pub share_price: U256,
    pub longs_outstanding: U256,
    pub long_average_maturity_time: U256,
    pub shorts_outstanding: U256,
    pub short_average_maturity_time: U256,
    pub withdrawal_shares_ready_to_withdraw: U256,
    pub withdrawal_shares_proceeds: U256,
    pub lp_share_price: U256,
    pub long_exposure: U256,
}

#[derive(Serialize, Deserialize)]
pub struct WasmState {
    pub config: WasmPoolConfig,
    pub info: WasmPoolInfo,
}

impl From<&WasmState> for State {
    fn from(wasm_state: &WasmState) -> State {
        State {
            config: PoolConfig {
                base_token: wasm_state.config.base_token,
                governance: wasm_state.config.governance,
                fee_collector: wasm_state.config.fee_collector,
                fees: Fees {
                    curve: wasm_state.config.fees.curve,
                    flat: wasm_state.config.fees.flat,
                    governance: wasm_state.config.fees.governance,
                },
                initial_share_price: wasm_state.config.initial_share_price,
                minimum_share_reserves: wasm_state.config.minimum_share_reserves,
                minimum_transaction_amount: wasm_state.config.minimum_transaction_amount,
                time_stretch: wasm_state.config.time_stretch,
                position_duration: wasm_state.config.position_duration,
                checkpoint_duration: wasm_state.config.checkpoint_duration,
                oracle_size: wasm_state.config.oracle_size,
                update_gap: wasm_state.config.update_gap,
            },
            info: PoolInfo {
                share_reserves: wasm_state.info.share_reserves,
                bond_reserves: wasm_state.info.bond_reserves,
                long_exposure: wasm_state.info.long_exposure,
                share_price: wasm_state.info.share_price,
                longs_outstanding: wasm_state.info.longs_outstanding,
                shorts_outstanding: wasm_state.info.shorts_outstanding,
                long_average_maturity_time: wasm_state.info.long_average_maturity_time,
                short_average_maturity_time: wasm_state.info.short_average_maturity_time,
                lp_total_supply: wasm_state.info.lp_total_supply,
                lp_share_price: wasm_state.info.lp_share_price,
                withdrawal_shares_proceeds: wasm_state.info.withdrawal_shares_proceeds,
                withdrawal_shares_ready_to_withdraw: wasm_state
                    .info
                    .withdrawal_shares_ready_to_withdraw,
            },
        }
    }
}
