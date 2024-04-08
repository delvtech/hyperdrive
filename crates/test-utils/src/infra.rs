/// This module contains utilities that abstract away the process of interacting
/// with delvtech/infra deployments.
use std::time::Duration;

use eyre::{eyre, Result};
use hyperdrive_addresses::Addresses;
use tokio::time::sleep;

const RETRIES: usize = 5;
const RETRY_TIME: Duration = Duration::from_millis(500);

pub async fn query_addresses(artifacts_url: &str) -> Result<Addresses> {
    // Poll the artifacts server for the hyperdrive addresses.
    let mut maybe_addresses = None;
    for _ in 0..RETRIES {
        let response = reqwest::get(artifacts_url).await?;
        if response.status().is_success() {
            maybe_addresses = Some(response.json::<Addresses>().await?);
            break;
        } else {
            sleep(RETRY_TIME).await;
        }
    }
    maybe_addresses.ok_or(eyre!(
        "couldn't get hyperdrive addresses after {} retries",
        RETRIES
    ))
}
