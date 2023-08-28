import "CVLMath.spec";

/// The ultimate summary for calculatePresentValue(params)
function CVLPresentValue(HyperdriveMath.PresentValueParams params) returns uint256 {
    mathint result;
    mathint _netCurveTrade = netCurveTrade(params);
    if(_netCurveTrade > 0) {
        result = params.shareReserves - params.minimumShareReserves
            + CVLNetFlatTrade(params)
            + CVLNetCurveTrade_positive(params, _netCurveTrade);
    }
    else {
        result = params.shareReserves - params.minimumShareReserves
            + CVLNetFlatTrade(params)
            + CVLNetCurveTrade_negative(params, 0-_netCurveTrade);
    }
    return require_uint256(result);
}

function netCurveTrade(HyperdriveMath.PresentValueParams params) returns mathint {
    return 
        mulDownWad(params.longsOutstanding, params.longAverageTimeRemaining) - 
        mulDownWad(params.shortsOutstanding, params.shortAverageTimeRemaining);
}

/// A summary (over-approximation) for the positive net curve trade contribution to the PV.
function CVLNetCurveTrade_positive(HyperdriveMath.PresentValueParams params, mathint absNetCurve) returns mathint {
    mathint totalTrade;
    /// Introduce axioms for the positive branch (closing as many longs as possible)
    /// require ClosingLongsAxioms(params, absNetCurve).
    return totalTrade;
}

/// A summary (over-approximation) for the negative net curve trade contribution to the PV.
function CVLNetCurveTrade_negative(HyperdriveMath.PresentValueParams params, mathint absNetCurve) returns mathint {
    mathint totalTrade;
    /// Introduce axioms for the negative branch (closing as many shorts as possible)
    /// require ClosingShortsAxioms(params, absNetCurve). 
    return totalTrade;
}

/// Function that returns the conjuction of all axioms for the netFlatTrade value.
/// Used for expressing summary behavior.
function netFlatTrade_axioms(HyperdriveMath.PresentValueParams params, mathint value) returns bool {
    return (value <= to_mathint(divDownWad(params.shortsOutstanding, params.sharePrice)))
        && (value >= 0 - divDownWad(params.longsOutstanding, params.sharePrice));

    /// Alternate axiom:
    // return value * params.sharePrice <= params.shortsOutstanding * ONE18() 
    //    && value * params.sharePrice + params.longsOutstanding * ONE18() >= 0;
}

/// A summary (over-approximation) for netFlatTrade
function CVLNetFlatTrade(HyperdriveMath.PresentValueParams params) returns mathint {
    mathint netFlat;
    require netFlatTrade_axioms(params, netFlat);
    return netFlat;
}

/// The actual implementation of HyperdriveMath netFlatTrade.
function netFlatTrade(HyperdriveMath.PresentValueParams params) returns mathint {
    uint256 tp_shorts = require_uint256(ONE18() - params.shortAverageTimeRemaining);
    uint256 tp_longs = require_uint256(ONE18() - params.longAverageTimeRemaining);

    return 
        mulDivDownAbstractPlus(params.shortsOutstanding, tp_shorts, params.sharePrice) - 
        mulDivDownAbstractPlus(params.longsOutstanding, tp_longs, params.sharePrice);
}

/// A rule for checking that the actual implementation satisfies the over approximation behavior.
rule netFlatTradeAxiomsTest(HyperdriveMath.PresentValueParams params) {
    mathint result = netFlatTrade(params);
    assert netFlatTrade_axioms(params, result);
}
