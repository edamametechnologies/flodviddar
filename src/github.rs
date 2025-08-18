use std::io::Read;
use std::process::Command;
use zip::ZipArchive;

pub struct GithubApi {
    run_id: String,
    repo: String,
}

#[derive(serde::Deserialize, Debug)]
pub struct Artifact {
    id: u64,
    name: String,
    size: u64,
    url: String,
}

#[derive(serde::Deserialize, Debug)]
pub struct GetAllArtifacts {
    total_count: u64,
    artifacts: Vec<Artifact>,
}

impl GithubApi {
    pub fn new() -> Self {
        let run_id = std::env::var("GITHUB_RUN_ID").expect("GITHUB_RUN_ID not set");
        let repo = std::env::var("GITHUB_REPOSITORY").expect("GITHUB_REPOSITORY not set");
        Self { run_id, repo }
    }

    async fn get_all_artifacts(&self) -> Result<Vec<Artifact>, String> {
        let repo = self.repo.clone();

        let output = Command::new("gh")
            .args([
                "api",
                "--paginate",
                &format!("/repos/{}/actions/artifacts", repo),
            ])
            .output()
            .expect("Failed to execute gh command");

        if !output.status.success() {
            eprintln!("gh command failed with {}", output.status);
        }

        let resp = serde_json::from_slice::<GetAllArtifacts>(&output.stdout)
            .map_err(|e| format!("Failed to parse response: {}", e))?;
        Ok(resp.artifacts)
    }

    async fn get_whitelist(&self, artifact_id: u64) -> Result<String, String> {
        let repo = self.repo.clone(); // "owner/repo"

        // Call gh api to get the ZIP
        let output = Command::new("gh")
            .args([
                "api",
                "-H",
                "Accept: application/zip",
                &format!("/repos/{repo}/actions/artifacts/{artifact_id}/zip"),
            ])
            .output()
            .map_err(|e| format!("Failed to run gh: {e}"))?;

        if !output.status.success() {
            return Err(format!(
                "gh api failed: {}",
                String::from_utf8_lossy(&output.stderr)
            ));
        }

        // Open the ZIP from memory
        let cursor = std::io::Cursor::new(output.stdout);
        let mut zip = ZipArchive::new(cursor).map_err(|e| format!("invalid ZIP: {e}"))?;

        // Look for whitelist.json
        let mut file = zip
            .by_name("whitelist.json")
            .map_err(|_| "whitelist.json not found in artifact".to_string())?;

        let mut contents = String::new();
        file.read_to_string(&mut contents)
            .map_err(|e| format!("read whitelist.json failed: {e}"))?;

        Ok(contents)
    }

    pub async fn get_whitelist_artifact(&self, artifact_name: &str) -> Result<String, String> {
        let get_all_artifacts = self.get_all_artifacts().await?;
        // Find the artifacts id and download it
        for artifact in get_all_artifacts {
            if artifact.name == artifact_name {
                println!("Found artifact: {}", artifact.name);
                return self.get_whitelist(artifact.id).await;
            }
            // Check if a augment file is present
            if artifact.name == format!("augment_{}.json", artifact_name) {
                println!("Found augment artifact: {}", artifact.name);
                return self.get_whitelist(artifact.id).await;
            }
        }
        Ok("".to_string())
    }

    // pub async fn restart_pipeline
}
