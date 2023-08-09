use ethers::prelude::Abigen;
use eyre::Result;
use heck::ToSnakeCase;
use std::io::Write;
use std::path::Path;
use std::process::Command;

fn get_artifacts(artifacts_path: &Path) -> Result<Vec<(String, String)>> {
    let mut artifacts = Vec::new();
    for entry in std::fs::read_dir(artifacts_path)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_file() {
            let source = path.clone().into_os_string().into_string().unwrap();
            let name = String::from(path.file_stem().unwrap().to_str().unwrap());
            if name.ends_with("Deployer") {
                // TODO: The Deployer contracts have a `deploy()` function that
                // conflicts with ethers-rs `deploy()` function. We should
                // update the deployer interface when we update the factory.
                continue;
            }
            artifacts.push((source, name));
        } else {
            artifacts.extend(get_artifacts(&path)?);
        }
    }
    Ok(artifacts)
}

fn main() -> Result<()> {
    // Re-run this script whenever the build script itself changes.
    println!("cargo:rerun-if-changed=build.rs");

    // Re-run this script whenever a contract may have changed.
    println!("cargo:rerun-if-changed=../../contracts/");
    println!("cargo:rerun-if-changed=../../test/");

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
            .generate()?
            .write_to_file(target_file)?;

        // Append the generated contract wrapper to the mod file.
        writeln!(mod_file, "pub mod {};", target)?;
    }

    Ok(())
}
