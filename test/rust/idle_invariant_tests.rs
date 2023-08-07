use ethers::types::U256;
use ethers::utils::parse_units;
use eyre::Result;
use test_utils::agent::Agent;
use test_utils::hyperdrive::Hyperdrive;

#[tokio::test]
async fn test_invariant() -> Result<()> {
    let deployment = Hyperdrive::new().await?;
    let mut alice = Agent::new(deployment.clone(), deployment.accounts[0].address());
    let mut bob = Agent::new(deployment.clone(), deployment.accounts[1].address());

    // Fund Alice and Bob's accounts.
    let contribution = U256::from(parse_units("500_000_000", 18)?);
    alice.fund(contribution).await?;
    bob.fund(contribution).await?;

    // Initialize the pool.
    let rate = U256::from(parse_units("0.05", 18)?);
    alice.initialize(rate, contribution).await?;

    // Bob opens a long position.
    let long_amount = U256::from(parse_units("100_000_000", 18)?);
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
