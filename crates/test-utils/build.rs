use ethers::prelude::Abigen;
use eyre::Result;
use std::process::Command;

fn main() -> Result<()> {
    // Re-run this script whenever the build script itself changes.
    println!("cargo:rerun-if-changed=build.rs");

    // Re-run this script whenever a contract may have changed.
    println!("cargo:rerun-if-changed=../../contracts/");
    println!("cargo:rerun-if-changed=../../test/");

    // Compile the contracts.
    Command::new("forge").args(&["build"]).status()?;

    // Generate the relevant contract wrappers.
    let generated = std::path::Path::new(std::env!("CARGO_MANIFEST_DIR")).join("src/generated");
    std::fs::create_dir_all(&generated)?;
    let abi_sources = vec![
        (
            "../../out/ERC20Mintable.sol/ERC20Mintable.json",
            "erc20_mintable.rs",
            "ERC20Mintable",
        ),
        (
            "../../out/ERC4626Hyperdrive.sol/ERC4626Hyperdrive.json",
            "erc4626_hyperdrive.rs",
            "ERC4626Hyperdrive",
        ),
        (
            "../../out/ERC4626DataProvider.sol/ERC4626DataProvider.json",
            "erc4626_data_provider.rs",
            "ERC4626DataProvider",
        ),
        (
            "../../out/IHyperdrive.sol/IHyperdrive.json",
            "ihyperdrive.rs",
            "IHyperdrive",
        ),
        (
            "../../out/Mock4626.sol/Mock4626.json",
            "mock4626.rs",
            "Mock4626",
        ),
    ];
    for (source, target, name) in abi_sources {
        let target_file = generated.join(target);
        if target_file.exists() {
            std::fs::remove_file(&target_file)?;
        }
        Abigen::new(name, source)?
            .generate()?
            .write_to_file(target_file)?;
    }

    Ok(())
}
