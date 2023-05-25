import "HyperdriveStorage.spec";

methods {
    function sharePrice() external returns (uint256); // Equivalent to c
}

definition LP_ASSET_ID() returns uint256 = 0;
definition WITHDRAWAL_SHARE_ASSET_ID() returns uint256 = (3 << 248);

/// Constants to be used in the verification
definition initialSharePrice0() returns uint256 = 10^18;
definition timeStretch0() returns uint256 = 45071688063194104;
definition checkpointDuration0() returns uint256 = 86400;
definition positionDuration0() returns uint256 = 31536000;
definition updateGap0() returns uint256 = 1000;
definition curveFee0() returns mathint = 10^18 / 10;
definition flatFee0() returns mathint = 10^18 / 10;
definition governanceFee0() returns mathint = 10^18 / 10;

/// ======================================
///             GHOSTS
/// ======================================

ghost mathint _ghostReadyToWithdraw {
    init_state axiom _ghostReadyToWithdraw == 0; 
}

ghost mathint _sumOfWithdrawalShares {
    init_state axiom _sumOfWithdrawalShares == 0; 
}

ghost mathint _sumOfLPTokens {
    init_state axiom _sumOfLPTokens == 0;
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

hook Sload uint128 value currentContract._withdrawPool.readyToWithdraw STORAGE {
    require _ghostReadyToWithdraw == to_mathint(value);
}

hook Sstore currentContract._withdrawPool.readyToWithdraw uint128 value (uint128 old_value) STORAGE {
    _ghostReadyToWithdraw = to_mathint(value);
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

/// lr : Withdrawal shares that are ready to redeem.
function readyToRedeemShares() returns mathint {
    return _ghostReadyToWithdraw;
}

/// The total LP shares liquidity (corresponds to present value of LP)
function LP_Liquidity() returns mathint {
    return totalLPSupply() + totalWithdrawalShares() - readyToRedeemShares();
}

/// Fixed interest per curve (+1)
/// r + 1 = y/(z*mu)
function curveFixedInterest() returns mathint {
    return stateShareReserves() == 0 ? 0 : (stateBondReserves() * ONE18()) / (stateShareReserves() * initialSharePrice());
}
