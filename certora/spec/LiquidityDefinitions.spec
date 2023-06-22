import "HyperdriveStorage.spec";

methods {
    function sharePrice() external returns (uint256);
}

definition LP_ASSET_ID() returns uint256 = 0;
definition WITHDRAWAL_SHARE_ASSET_ID() returns uint256 = (3 << 248);

definition isAddLiq(method f) returns bool = 
    f.selector == sig:addLiquidity(uint256,uint256,uint256,address,bool).selector;

definition isRemoveLiq(method f) returns bool = 
    f.selector == sig:removeLiquidity(uint256,uint256,address,bool).selector;

definition isOpenLong(method f) returns bool = 
    f.selector == sig:openLong(uint256,uint256,address,bool).selector;

definition isCloseLong(method f) returns bool = 
    f.selector == sig:closeLong(uint256,uint256,uint256,address,bool).selector;

definition isOpenShort(method f) returns bool = 
    f.selector == sig:openShort(uint256,uint256,address,bool).selector;

definition isCloseShort(method f) returns bool = 
    f.selector == sig:closeShort(uint256,uint256,uint256,address,bool).selector;

/// Constants to be used in the verification
definition initialSharePrice0() returns uint256 = 10^18;
definition timeStretch0() returns uint256 = 45071688063194104;
definition checkpointDuration0() returns uint256 = 86400;
definition positionDuration0() returns uint256 = 31536000;
definition updateGap0() returns uint256 = 1000;
definition curveFee0() returns mathint = 10^18 / 10;
definition flatFee0() returns mathint = 10^18 / 10;
definition governanceFee0() returns mathint = 10^18 / 10;
/// Based on AssetId library
definition timeByID(uint256 ID) returns mathint = ((1 << 248) - 1) & ID;
definition prefixByID(uint256 ID) returns mathint = (ID >> 248);

/// ======================================
///             GHOSTS
/// ======================================

/// Mirror of totalSupply
ghost mapping(uint256 => uint256) ghostTotalSupply;

ghost mathint _sumOfWithdrawalShares {
    init_state axiom _sumOfWithdrawalShares == 0; 
}

ghost mathint _sumOfLPTokens {
    init_state axiom _sumOfLPTokens == 0;
}

ghost mathint _sumOfLongs{
    init_state axiom _sumOfLongs == 0;
}

ghost mathint _sumOfShorts{
    init_state axiom _sumOfShorts == 0;
}

/// ======================================
///             HOOKS
/// ======================================

hook Sstore currentContract._balanceOf[KEY uint256 tokenID][KEY address account] uint256 value (uint256 old_value) STORAGE {
    _sumOfWithdrawalShares = tokenID == WITHDRAWAL_SHARE_ASSET_ID() ? 
        _sumOfWithdrawalShares + value - old_value : _sumOfWithdrawalShares;

    _sumOfLPTokens = tokenID == LP_ASSET_ID() ?
        _sumOfLPTokens + value - old_value : _sumOfLPTokens;
}

hook Sload uint256 value currentContract._totalSupply[KEY uint256 tokenID] STORAGE {
    mathint prefix = prefixByID(tokenID);

    require(ghostTotalSupply[tokenID] == value);
    if(prefix == 1) {require _sumOfLongs >= to_mathint(value);}
    else if(prefix == 2) {require _sumOfShorts >= to_mathint(value);}
}

hook Sstore currentContract._totalSupply[KEY uint256 tokenID] uint256 value (uint256 old_value) STORAGE {
    mathint prefix = prefixByID(tokenID);
    //mathint time = timeByID(tokenID);
    ghostTotalSupply[tokenID] = value;

    _sumOfLongs = (prefix == 1) ?
        _sumOfLongs + value - old_value : _sumOfLongs;

    _sumOfShorts = (prefix == 2) ?
        _sumOfShorts + value - old_value : _sumOfShorts;
}

/*
I + Iv + Lx + Lf + Lu + Lv: _marketState.shareReserves * _pricePerShare()
Lx + Lf + Lu: _marketState.longsOutstanding
(Lx + Lf + Lu + Lv) / (Lx + Lf + Lu): _pricePerShare() / _marketState.longOpenSharePrice
Sx + Sf + Su: _marketState.shortsOutstanding
Sx: _marketState.shortBaseVolume
W + Wv: _withdrawPool.proceeds * _pricePerShare()
(x, y): Bond pricing curve reserve consisting of base x and bonds y. (Note: In the implementation, yield source shares z is used instead of x.)
x: _marketState.shareReserves * _pricePerShare()
y: _marketState.bondReserves
*/

/// l: Total LP token supply
function totalLPSupply() returns mathint {
    return to_mathint(totalSupplyByToken(LP_ASSET_ID()));
}

/// Sum of LP tokens for all accounts
function sumOfLPTokens() returns mathint {
    return _sumOfLPTokens;
}

/// lw : Total withdrawal shares
function totalWithdrawalShares() returns mathint {
    return to_mathint(totalSupplyByToken(WITHDRAWAL_SHARE_ASSET_ID()));
}

/// Sum of withdrawal shares for all accounts
function sumOfWithdrawalShares() returns mathint {
    return _sumOfWithdrawalShares;
}

/// ol : Outstanding longs
function sumOfLongs() returns mathint {
    return _sumOfLongs;
}

/// os : Outstanding shorts
function sumOfShorts() returns mathint {
    return _sumOfShorts;
}

/// lr : Withdrawal shares that are ready to redeem.
function readyToRedeemShares() returns mathint {
    return to_mathint(withdrawPoolReadyShares());
}

/// z_withdrawals : Total withdrawal proceeds that are ready to be redeemed.
function withdrawalProceeds() returns mathint {
    return to_mathint(withdrawPoolProceeds());
}

/// The total LP shares liquidity (corresponds to present value of LP)
function LP_Liquidity() returns mathint {
    return totalLPSupply() + totalWithdrawalShares() - readyToRedeemShares();
}

/// Fixed interest per curve (+1)
/// r + 1 = y/(z*mu)
function curveFixedInterest() returns mathint {
    return stateShareReserves() == 0 ? 0 : to_mathint(divUpWad(stateBondReserves(), mulUpWad(stateShareReserves(), initialSharePrice())));
}

/// Average maturity time for longs
function AvgMTimeLongs() returns mathint {
    IHyperdrive.MarketState Mstate = marketState();
    return to_mathint(Mstate.longAverageMaturityTime);
}

/// Average maturity time for shorts
function AvgMTimeShorts() returns mathint {
    IHyperdrive.MarketState Mstate = marketState();
    return to_mathint(Mstate.shortAverageMaturityTime);
}