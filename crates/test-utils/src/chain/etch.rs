/// This module contains implementations on the `Chain` struct that make it easy
/// to debug live Hyperdrive pools.
use ethers::{
    providers::Middleware,
    signers::Signer,
    types::{Address, Bytes},
};
use eyre::Result;
use fixed_point_macros::uint256;
use hyperdrive_addresses::Addresses;
use hyperdrive_wrappers::wrappers::{
    erc20_mintable::ERC20Mintable, erc4626_hyperdrive::ERC4626Hyperdrive,
    erc4626_target0::ERC4626Target0, erc4626_target1::ERC4626Target1,
    erc4626_target2::ERC4626Target2, erc4626_target3::ERC4626Target3,
    erc4626_target4::ERC4626Target4, etching_vault::EtchingVault, ihyperdrive::IHyperdrive,
    mock_erc4626::MockERC4626,
};

use super::Chain;

impl Chain {
    /// Etches the latest compiled bytecode onto a target instance of Hyperdrive.
    pub async fn etch<S: Signer + 'static>(&self, signer: S, addresses: &Addresses) -> Result<()> {
        // Set up the client.
        let client = self.client(signer).await?;

        // Instantiate a hyperdrive contract wrapper to use during the etching
        // process.
        let hyperdrive = IHyperdrive::new(addresses.erc4626_hyperdrive, client.clone());

        // Get the contract addresses of the vault and the targets.
        let target0_address = hyperdrive.target_0().call().await?;
        let target1_address = hyperdrive.target_1().call().await?;
        let target2_address = hyperdrive.target_2().call().await?;
        let target3_address = hyperdrive.target_3().call().await?;
        let target4_address = hyperdrive.target_4().call().await?;
        let vault_address = hyperdrive.vault_shares_token().call().await?;

        // Deploy templates for each of the contracts that should be etched and
        // get a list of targets and templates. In order for the contracts to
        // have the same behavior after etching, the storage layout needs to be
        // identical, and we must faithfully copy over the immutables from the
        // original contracts to the templates.
        let etch_pairs = {
            let mut pairs = Vec::new();

            // Deploy the base token template.
            let base = ERC20Mintable::new(addresses.base_token, client.clone());
            let name = base.name().call().await?;
            let symbol = base.symbol().call().await?;
            let decimals = base.decimals().call().await?;
            let is_competition_mode = base.is_competition_mode().call().await?;
            let base_template = ERC20Mintable::deploy(
                client.clone(),
                (name, symbol, decimals, Address::zero(), is_competition_mode),
            )?
            .send()
            .await?;
            pairs.push((addresses.base_token, base_template.address()));

            // Deploy the vault template.
            let vault = MockERC4626::new(vault_address, client.clone());
            let asset = vault.asset().call().await?;
            let name = vault.name().call().await?;
            let symbol = vault.symbol().call().await?;
            let is_competition_mode = vault.is_competition_mode().call().await?;
            let vault_template = MockERC4626::deploy(
                client.clone(),
                (
                    asset,
                    name,
                    symbol,
                    uint256!(0),
                    Address::zero(),
                    is_competition_mode,
                ),
            )?
            .send()
            .await?;
            pairs.push((vault_address, vault_template.address()));

            // Deploy the target0 template.
            let config = hyperdrive.get_pool_config().call().await?;
            let target0_template =
                ERC4626Target0::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target0_address, target0_template.address()));

            // Deploy the target1 template.
            let target1_template =
                ERC4626Target1::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target1_address, target1_template.address()));

            // Deploy the target2 template.
            let target2_template =
                ERC4626Target2::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target2_address, target2_template.address()));

            // Deploy the target3 template.
            let target3_template =
                ERC4626Target3::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target3_address, target3_template.address()));

            // Deploy the target4 template.
            let target4_template =
                ERC4626Target4::deploy(client.clone(), (config.clone(), vault_address))?
                    .send()
                    .await?;
            pairs.push((target4_address, target4_template.address()));

            // Etch the "etching vault" onto the current vault contract. The
            // etching vault implements `convertToAssets` to return the immutable
            // that was passed on deployment. This is necessary because the
            // ERC4626Hyperdrive instance verifies that the initial vault share price
            // is equal to the `_pricePerVaultShare`.
            let etching_vault_template = EtchingVault::deploy(
                client.clone(),
                (addresses.base_token, config.initial_vault_share_price),
            )?
            .send()
            .await?;
            let code = client
                .get_code(etching_vault_template.address(), None)
                .await?;
            client
                .provider()
                .request::<(Address, Bytes), ()>("anvil_setCode", (vault_address, code))
                .await?;

            // Deploy the hyperdrive template.
            let hyperdrive_template = ERC4626Hyperdrive::deploy(
                client.clone(),
                (
                    config,
                    target0_address,
                    target1_address,
                    target2_address,
                    target3_address,
                    target4_address,
                    vault_address,
                    Vec::<Address>::new(),
                ),
            )?
            .send()
            .await?;
            pairs.push((addresses.erc4626_hyperdrive, hyperdrive_template.address()));

            pairs
        };

        // Etch over the original contracts with the template contracts' code.
        for (target, template) in etch_pairs {
            let code = client.get_code(template, None).await?;
            client
                .provider()
                .request::<(Address, Bytes), ()>("anvil_setCode", (target, code))
                .await?;
        }

        Ok(())
    }
}
