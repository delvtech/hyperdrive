import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";
import "./LiquidityDefinitions.spec";

using DummyERC20A as baseToken;

methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);

    function _.recordPrice(uint256 price) internal => NONDET;
}

/// Maximum share price of the Hyperdrive
definition MaxSharePrice() returns mathint = ONE18() * 1000;

definition isInitialize(method f) returns bool = 
    f.selector == sig:initialize(uint256,uint256,address,bool).selector;

/// @dev Under-approximation of the pool parameters (based on developers' test)
/// @notice Use only to find violations!
function setHyperdrivePoolParams() {
    require initialSharePrice() == ONE18();
    require timeStretch() == 45071688063194104; /// 5% APR
    require checkpointDuration() == 86400;
    require positionDuration() == 31536000;
    require updateGap() == 1000;
    /// Realistic conditions
    require require_uint256(stateShareReserves()) == ONE18();
    require require_uint256(stateBondReserves()) >= ONE18();
}

/// A hook for loading the checkpoint prices
/// @notice To focus on realistic values, we assume the checkpoint was either not set
/// (zero price), or that the price is bounded between 1 and 1000.
hook Sload uint128 price currentContract._checkpoints[KEY uint256 timestamp].sharePrice STORAGE {
    require (price == 0) || (require_uint256(price) >= ONE18() && to_mathint(price) <= MaxSharePrice());
}