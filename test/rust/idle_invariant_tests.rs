use eyre::Result;
use fixed_point::FixedPoint;
use fixed_point_macros::fixed;
use test_utils::agent::Agent;
use test_utils::hyperdrive::Hyperdrive;

#[tokio::test]
async fn test_invariant() -> Result<()> {
    let deployment = Hyperdrive::new().await?;
    let mut alice = Agent::new(deployment.clone(), deployment.accounts[0].address());
    let mut bob = Agent::new(deployment.clone(), deployment.accounts[1].address());

    // Fund Alice and Bob's accounts.
    let contribution = fixed!(500_000_000e18);
    alice.fund(contribution).await?;
    bob.fund(contribution).await?;

    // Initialize the pool.
    let rate = fixed!(0.05e18);
    alice.initialize(rate, contribution).await?;

    // Bob opens a long position.
    let long_amount = fixed!(100_000_000e18);
    bob.open_long(long_amount).await?;

    println!("bob={:?}", bob);

    // FIXME: For a basic invariant test, we need to be able to randomly open
    // and close trades with different private keys.
    //
    // 1. Create a function that randomly generates new actions.
    // 2. Sample these actions in a loop.
    // 3. For each action (or some subset of the actions), verify that the
    //    invariants hold.
    //
    // For the invariant test that I want for the idle PR, I should randomly
    // open trades, close trades, add liquidity, remove liquidity, redeem
    // withdrawal shares, and advance the time to accrue interest. After
    // Hyperdrive is interacted with, the pool's idle should not exceed the
    // present value of the active LPs.
    //
    // We should also write invariant tests for the present value calculations.

    Ok(())
}
