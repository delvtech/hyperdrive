use std::{io::Write, path::Path, process::Command};

use ethers::prelude::Abigen;
use eyre::Result;
use heck::ToSnakeCase;

const TARGETS: &[&str] = &[
    // Interfaces
    "IERC20",
    "IERC4626Hyperdrive",
    "IHyperdrive",
    // Tokens
    "ERC20Mintable",
    // Hyperdrive
    "ERC4626Hyperdrive",
    "ERC4626Target0",
    "ERC4626Target1",
    "ERC4626Target2",
    "ERC4626Target3",
    // Test Contracts
    "ERC20Mintable",
    "EtchingVault",
    "MockERC4626",
    "MockFixedPointMath",
    "MockHyperdriveMath",
    "MockLPMath",
    "MockYieldSpaceMath",
];

fn get_artifacts(artifacts_path: &Path) -> Result<Vec<(String, String)>> {
    let mut artifacts = Vec::new();
    for entry in std::fs::read_dir(artifacts_path)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_file() {
            let source = path.clone().into_os_string().into_string().unwrap();
            let name = String::from(path.file_stem().unwrap().to_str().unwrap());

            // If the artifact is one of our targets, add it to the list.
            if TARGETS.contains(&name.as_str()) {
                artifacts.push((source, name));
            }
        } else {
            artifacts.extend(get_artifacts(&path)?);
        }
    }
    Ok(artifacts)
}

fn main() -> Result<()> {
    // Re-run this script whenever the build script itself or a contract changes.
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-changed=../../contracts/");

    // Compile the contracts.
    Command::new("forge").args(["build"]).status()?;

    // If there is an existing `wrappers` module, remove it. Then prepare to
    // re-write these files.
    let root = Path::new(std::env!("CARGO_MANIFEST_DIR"));
    let generated = root.join("src/wrappers");
    if generated.exists() {
        std::fs::remove_dir_all(&generated)?;
    }
    std::fs::create_dir_all(&generated)?;
    let mod_file = generated.join("mod.rs");
    let mut mod_file = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .open(mod_file)?;

    // Generate the relevant contract wrappers from Foundry's artifacts.
    let artifacts = root.join("../../out");
    let mut artifacts = get_artifacts(&artifacts)?;
    artifacts.sort_by(|a, b| a.1.cmp(&b.1));
    artifacts.dedup_by(|a, b| a.1.eq(&b.1));
    for (source, name) in artifacts {
        // Write the generated contract wrapper.
        let target = name.to_snake_case();
        let target_file = generated.join(format!("{}.rs", target));
        Abigen::new(name, source)?
            .add_derive("serde::Serialize")?
            .add_derive("serde::Deserialize")?
            .generate()?
            .write_to_file(target_file)?;

        // Append the generated contract wrapper to the mod file.
        writeln!(mod_file, "pub mod {};", target)?;
    }

    Ok(())
}
