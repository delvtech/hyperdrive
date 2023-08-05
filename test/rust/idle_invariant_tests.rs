use ethers::types::U256;
use ethers::utils::parse_units;
use eyre::Result;
use test_utils::hyperdrive::Hyperdrive;

#[tokio::test]
async fn test_invariant() -> Result<()> {
    let deployment = Hyperdrive::new().await?;
    let alice = deployment.accounts[0].clone();
    let hyperdrive = &deployment.hyperdrive;
    let base = &deployment.base;
    let config = hyperdrive.get_pool_config().call().await?;

    // Mint some base and approve the Hyperdrive instance.
    let contribution = U256::from(parse_units("500_000_000", 18)?);
    base.mint(contribution).send().await?;
    base.approve(hyperdrive.address(), U256::MAX).send().await?;

    // Initialize the pool.
    let rate = U256::from(parse_units("0.05", 18)?);
    hyperdrive
        .initialize(contribution, rate, alice.address(), true)
        .send()
        .await?;
    let lp_shares = hyperdrive
        .balance_of(U256::zero(), alice.address())
        .call()
        .await?;
    assert_eq!(
        lp_shares,
        contribution - config.minimum_share_reserves * U256::from(2)
    );

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
