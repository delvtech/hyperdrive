import "./erc20.spec";
import "./MathSummaries.spec";
import "./Sanity.spec";
import "./HyperdriveStorage.spec";
import "./LiquidityDefinitions.spec";

using AaveHyperdrive as HDAave;
using DummyATokenA as aToken;
using Pool as pool;
using MockAssetId as assetId;
using DummyERC20A as baseToken;

use rule sanity;

methods {
    function _.mint(address,address,uint256,uint256) external => DISPATCHER(true);
    function _.burn(address,address,uint256,uint256) external => DISPATCHER(true);

    function aToken.UNDERLYING_ASSET_ADDRESS() external returns (address) envfree;
    function pool.liquidityIndex(address,uint256) external returns (uint256) envfree;
    function totalShares() external returns (uint256) envfree;

    function MockAssetId.encodeAssetId(AssetId.AssetIdPrefix, uint256) external returns (uint256) envfree;
    function _.recordPrice(uint256 price) internal => NONDET;
}

/// Aave pool aToken indices
definition indexA() returns uint256 = require_uint256(RAY()*2);
definition indexB() returns uint256 = require_uint256((RAY()*125)/100);
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

/// A hook for loading the Aave pool liquidity index
hook Sload uint256 index Pool.liquidityIndex[KEY address token][KEY uint256 timestamp] STORAGE {
    /// @WARNING : UNDER-APPROXIMATION!
    /// @notice : to simplify the SMT formulas, we assume a specific value for the index.
    /// so in general, the index as a function of time is actually a constant.
    require index == indexA();
}

/// A hook for loading the checkpoint prices
/// @notice To focus on realistic values, we assume the checkpoint was either not set
/// (zero price), or that the price is bounded between 1 and 100.
hook Sload uint128 price currentContract._checkpoints[KEY uint256 timestamp].sharePrice STORAGE {
    require (price == 0) || (require_uint256(price) >= ONE18() && to_mathint(price) <= MaxSharePrice());
}

function getPoolIndex(uint256 timestamp) returns uint256 {
    return pool.liquidityIndex(aToken.UNDERLYING_ASSET_ADDRESS(), timestamp);
}

/// @notice Simulates the output of the `_deposit()` function
/// @param totalSharesBefore - totalShares before deposit function
/// @param assetsBefore - assets of contract before deposit function.
/// @param baseAmount - The amount of token to transfer
/// @param asUnderlying - underlying tokens (true) or yield source tokens (false)
/// @return output[0] = sharesMinted
/// @return output[1] = sharePrice
function depositOutput(env e, uint256 totalSharesBefore, uint256 assetsBefore, uint256 baseAmount, bool asUnderlying) returns uint256[2] {
    uint256[2] output;
    uint256 totalSharesAfter = totalShares();
    uint256 assetsAfter = aToken.balanceOf(e, HDAave);
    uint256 index = getPoolIndex(e.block.timestamp);

    if(totalSharesBefore == 0) {
        require baseAmount == output[0];
        require ONE18() == output[1];
    }
    else {
        if(asUnderlying) {
            require baseAmount > 0 => assetsBefore < assetsAfter;
        }
        else {
            require to_mathint(assetsAfter) >= assetsBefore + baseAmount;
            require to_mathint(assetsAfter) <= assetsBefore + baseAmount + index/RAY();
        }
        require mulDivDownAbstractPlus(totalSharesBefore, baseAmount, assetsBefore) == output[0];
        require mulDivDownAbstractPlus(baseAmount, ONE18(), output[0]) == output[1];
        require totalSharesBefore + output[0] == to_mathint(totalSharesAfter);
    }
    return output;
}