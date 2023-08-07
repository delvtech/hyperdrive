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
    Command::new("forge").args(&["build"]).status()?;

    // Create the generated directory if it doesn't exist and delete any
    // existing mod file for the generated module.
    let root = Path::new(std::env!("CARGO_MANIFEST_DIR"));
    let generated = root.join("src/wrappers");
    std::fs::create_dir_all(&generated)?;
    println!("1");
    let mod_file = generated.join("mod.rs");
    let mut mod_file = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .open(mod_file)?;
    println!("2");

    // Generate the relevant contract wrappers from Foundry's artifacts.
    let artifacts = root.join("../../out");
    let mut artifacts = get_artifacts(&artifacts)?;
    artifacts.sort_by(|a, b| a.1.cmp(&b.1));
    artifacts.dedup_by(|a, b| a.1.eq(&b.1));
    println!("artifacts={:?}", artifacts);
    for (source, name) in artifacts {
        // Write the generated contract wrapper.
        let target = name.to_snake_case();
        let target_file = generated.join(format!("{}.rs", target));
        if target_file.exists() {
            std::fs::remove_file(&target_file)?;
        }
        Abigen::new(name, source)?
            .generate()?
            .write_to_file(target_file)?;

        // Append the generated contract wrapper to the mod file.
        writeln!(mod_file, "pub mod {};", target)?;
    }

    Ok(())
}
