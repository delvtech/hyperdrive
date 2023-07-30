use crate::fixed_point::FixedPoint;

struct State {
    z: FixedPoint,
    y: FixedPoint,
    c: FixedPoint,
    // FIXME: How do we prevent this from being mutated?
    mu: FixedPoint,
    ts: FixedPoint,
}

impl State {
    // FIXME: Implement all of the YieldSpace math.
}
