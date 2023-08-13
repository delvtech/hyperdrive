use ethers::core::types::{Address, U256, I256};
use hyperdrive_wrappers::wrappers::i_hyperdrive::{Fees, PoolConfig, PoolInfo};
use pyo3::exceptions::PyValueError;
use pyo3::prelude::*;
use pyo3::PyErr;

use hyperdrive_math::hyperdrive_math::State;

#[pyclass(name = "HyperdriveState")]
pub struct PyState {
    pub state: State,
}

impl PyState {
    pub(crate) fn new(state: State) -> Self {
        PyState { state }
    }
}

impl From<State> for PyState {
    fn from(state: State) -> Self {
        PyState { state }
    }
}
pub struct PyPoolConfig {
    pub pool_config: PoolConfig,
}

// Helper function to extract U256 values from Python object attributes
fn extract_u256_from_attr(ob: &PyAny, attr: &str) -> PyResult<U256> {
    let value_str: String = ob.getattr(attr)?.extract()?;
    U256::from_dec_str(&value_str)
        .map_err(|e| PyErr::new::<PyValueError, _>(format!("Invalid U256 for {}: {}", attr, e)))
}

// Helper function to extract I256 values from Python object attributes
fn extract_i256_from_attr(ob: &PyAny, attr: &str) -> PyResult<I256> {
    let value_str: String = ob.getattr(attr)?.extract()?;
    I256::from_dec_str(&value_str)
        .map_err(|e| PyErr::new::<PyValueError, _>(format!("Invalid I256 for {}: {}", attr, e)))
}

// Helper function to extract Ethereum Address values from Python object attributes
fn extract_address_from_attr(ob: &PyAny, attr: &str) -> PyResult<Address> {
    let address_str: String = ob.getattr(attr)?.extract()?;
    address_str.parse::<Address>().map_err(|e| {
        PyErr::new::<PyValueError, _>(format!("Invalid Ethereum address for {}: {}", attr, e))
    })
}

fn extract_fees_from_attr(ob: &PyAny, attr: &str) -> PyResult<Fees> {
    let fees_obj = ob.getattr(attr)?;

    let curve = extract_u256_from_attr(&fees_obj, "curve")?;
    let flat = extract_u256_from_attr(&fees_obj, "flat")?;
    let governance = extract_u256_from_attr(&fees_obj, "governance")?;

    Ok(Fees {
        curve,
        flat,
        governance,
    })
}

impl FromPyObject<'_> for PyPoolConfig {
    fn extract(ob: &PyAny) -> PyResult<Self> {
        let base_token = extract_address_from_attr(ob, "base_token")?;
        let initial_share_price = extract_u256_from_attr(ob, "initial_share_price")?;
        let minimum_share_reserves = extract_u256_from_attr(ob, "minimum_share_reserves")?;
        let position_duration = extract_u256_from_attr(ob, "position_duration")?;
        let checkpoint_duration = extract_u256_from_attr(ob, "checkpoint_duration")?;
        let time_stretch = extract_u256_from_attr(ob, "time_stretch")?;
        let governance = extract_address_from_attr(ob, "governance")?;
        let fees = extract_fees_from_attr(ob, "fees")?;
        let fee_collector = extract_address_from_attr(ob, "fee_collector")?;
        let oracle_size = extract_u256_from_attr(ob, "oracle_size")?;
        let update_gap = extract_u256_from_attr(ob, "update_gap")?;

        return Ok(PyPoolConfig {
            pool_config: PoolConfig {
                base_token,
                initial_share_price,
                minimum_share_reserves,
                position_duration,
                checkpoint_duration,
                time_stretch,
                governance,
                fees,
                fee_collector,
                oracle_size,
                update_gap,
            },
        });
    }
}

pub struct PyPoolInfo {
    pub pool_info: PoolInfo,
}

impl PyPoolInfo {
    pub(crate) fn new(pool_info: PoolInfo) -> Self {
        PyPoolInfo { pool_info }
    }
}

impl FromPyObject<'_> for PyPoolInfo {
    fn extract(ob: &PyAny) -> PyResult<Self> {
        let share_reserves = extract_u256_from_attr(ob, "share_reserves")?;
        let bond_reserves = extract_u256_from_attr(ob, "bond_reserves")?;
        let lp_total_supply = extract_u256_from_attr(ob, "lp_total_supply")?;
        let share_price = extract_u256_from_attr(ob, "share_price")?;
        let longs_outstanding = extract_u256_from_attr(ob, "longs_outstanding")?;
        let long_average_maturity_time = extract_u256_from_attr(ob, "long_average_maturity_time")?;
        let shorts_outstanding = extract_u256_from_attr(ob, "shorts_outstanding")?;
        let short_average_maturity_time =
            extract_u256_from_attr(ob, "short_average_maturity_time")?;
        let short_base_volume = extract_u256_from_attr(ob, "short_base_volume")?;
        let withdrawal_shares_ready_to_withdraw =
            extract_u256_from_attr(ob, "withdrawal_shares_ready_to_withdraw")?;
        let withdrawal_shares_proceeds = extract_u256_from_attr(ob, "withdrawal_shares_proceeds")?;
        let lp_share_price = extract_u256_from_attr(ob, "lp_share_price")?;
        let exposure = extract_i256_from_attr(ob, "exposure")?;

        let pool_info = PoolInfo {
            share_reserves,
            bond_reserves,
            lp_total_supply,
            share_price,
            longs_outstanding,
            long_average_maturity_time,
            shorts_outstanding,
            short_average_maturity_time,
            short_base_volume,
            withdrawal_shares_ready_to_withdraw,
            withdrawal_shares_proceeds,
            lp_share_price,
            exposure,
        };

        Ok(PyPoolInfo::new(pool_info))
    }
}

#[pymethods]
impl PyState {
    #[new]
    pub fn __init__(pool_config: &PyAny, pool_info: &PyAny) -> PyResult<Self> {
        let rust_pool_config = PyPoolConfig::extract(pool_config)?.pool_config;
        let rust_pool_info = PyPoolInfo::extract(pool_info)?.pool_info;
        let hyperdrive_state = State::new(rust_pool_config, rust_pool_info);
        Ok(PyState::new(hyperdrive_state))
    }

    pub fn get_spot_price(&self) -> PyResult<String> {
        let result_fp = self.state.get_spot_price();
        let result = U256::from(result_fp).to_string();
        return Ok(result);
    }
}

/// A pyO3 wrapper for the hyperdrie_math crate.  The State struct will be exposed with all methods
/// listed in #[pymethods] decorated impl.  The name of this function must match the `lib.name`
/// setting in the `Cargo.toml`, else Python will not be able to import the module.
#[pymodule]
#[pyo3(name = "hyperdrive_math")]
fn hyperdrive_math_lib(_py: Python, m: &PyModule) -> PyResult<()> {
    m.add_class::<PyState>().unwrap();
    Ok(())
}
