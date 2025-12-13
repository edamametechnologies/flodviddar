use std::{process::Command, time::Duration};
// Add daemon module
mod daemon;

use anyhow::Result;
use clap::{arg, ArgAction, Command as ClapCommand};
use flodbadd::{
    analyzer::SessionAnalyzer, capture::FlodbaddCapture, interface::get_valid_network_interfaces,
    sessions::format_sessions_log,
};
use tokio::time::sleep;

#[tokio::main]
async fn main() -> Result<()> {
    let mut cmd = build_cli();
    let matches = cmd.clone().get_matches();

    // Global verbosity handling (-v, -vv, -vvv)
    let verbose_level = matches.get_count("verbose");
    if verbose_level > 0 {
        let level = match verbose_level {
            1 => "info",
            2 => "debug",
            _ => "trace",
        };
        std::env::set_var("RUST_LOG", level);
        tracing_subscriber::fmt::init();
    }

    match matches.subcommand() {
        Some(("scan", sub)) => {
            let seconds = *sub.get_one::<u64>("SECONDS").unwrap_or(&120);
            let until_signal = sub.get_flag("until-signal");
            let custom_wl = sub
                .get_one::<String>("custom-whitelist")
                .map(|s| s.as_str());
            let output_mode = sub.get_one::<String>("output").map(|s| s.as_str());
            let check_whitelist = !sub.get_flag("no-whitelist");
            let check_blacklist = !sub.get_flag("no-blacklist");
            let check_anomaly = !sub.get_flag("no-anomaly");
            let cancel_pipeline = !sub.get_flag("no-cancel");
            scan(
                seconds,
                until_signal,
                output_mode,
                custom_wl,
                check_whitelist,
                check_blacklist,
                check_anomaly,
                cancel_pipeline,
            )
            .await?;
        }
        Some(("halt", sub)) => {
            let reason = sub.get_one::<String>("REASON").unwrap();
            halt_ci_pipeline(reason)?;
        }
        Some(("watch", sub)) => {
            let poll = *sub.get_one::<u64>("POLL").unwrap_or(&30);
            let check_whitelist = !sub.get_flag("no-whitelist");
            let check_blacklist = !sub.get_flag("no-blacklist");
            let check_anomaly = !sub.get_flag("no-anomaly");
            let cancel_pipeline = !sub.get_flag("no-cancel");
            let custom_wl = sub
                .get_one::<String>("custom-whitelist")
                .map(|s| s.as_str());
            daemon::watch_daemon(
                poll,
                check_whitelist,
                check_blacklist,
                check_anomaly,
                cancel_pipeline,
                custom_wl,
            )
            .await?;
        }
        Some(("create-whitelist", sub)) => {
            let seconds = *sub.get_one::<u64>("SECONDS").unwrap_or(&60);
            let augment = *sub.get_one::<bool>("AUGMENT").unwrap_or(&false);
            let output_path = sub.get_one::<String>("file").map(|s| s.as_str());
            create_whitelist(seconds, augment, output_path).await?;
        }
        _ => {
            // Unknown command prints help
            cmd.print_help()?;
        }
    }

    Ok(())
}

pub fn build_cli() -> ClapCommand {
    ClapCommand::new("flodviddar")
        .about("Flodviddar – CI-aware egress network threat detector")
        .arg(
            arg!( -v --verbose ... "Verbosity level (-v: info, -vv: debug, -vvv: trace)")
                .required(false)
                .action(ArgAction::Count)
                .global(true),
        )
        .subcommand(
            ClapCommand::new("scan")
                .about("Capture live traffic for the given duration and optionally fail the CI pipeline on violations")
                .arg(
                    arg!([SECONDS] "Number of seconds to capture (default 120)")
                        .required(false)
                        .value_parser(clap::value_parser!(u64)),
                )
                .arg(
                    arg!(--"custom-whitelist" <PATH> "Path to a custom whitelist JSON to load before scanning")
                        .required(false)
                        .value_parser(clap::value_parser!(String)),
                )
                .arg(
                    arg!(--"until-signal" "Run until Ctrl-C/SIGTERM instead of fixed duration")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    arg!(--output <MODE> "Output on exit: whitelist | report")
                        .required(false)
                        .value_parser(["whitelist", "report"]),
                )
                .arg(
                    arg!(--"no-whitelist" "Disable whitelist conformance check")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    arg!(--"no-blacklist" "Disable blacklist check")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    arg!(--"no-anomaly" "Disable anomaly check")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    arg!(--"no-cancel" "Do NOT cancel pipeline on violations (just exit 0)")
                        .required(false)
                        .action(ArgAction::SetTrue),
                ),
        )
        .subcommand(
            ClapCommand::new("halt")
                .about("Manually cancel the current CI pipeline")
                .arg(arg!(<REASON> "Reason for cancellation")
                    .required(true)
                    .value_parser(clap::value_parser!(String))),
        )
        .subcommand(
            ClapCommand::new("watch")
                .about("Continuously monitor traffic and stop pipeline in real-time on violations")
                .arg(
                    arg!([POLL] "Polling interval in seconds (default 30)")
                        .required(false)
                        .value_parser(clap::value_parser!(u64)),
                )
                .arg(
                    arg!(--"no-whitelist" "Disable whitelist conformance check")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    arg!(--"no-blacklist" "Disable blacklist check")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    arg!(--"no-anomaly" "Disable anomaly check")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    arg!(--"no-cancel" "Do NOT cancel pipeline on violations (just log)")
                        .required(false)
                        .action(ArgAction::SetTrue),
                )
                .arg(
                    arg!(--"custom-whitelist" <PATH> "Path to a custom whitelist JSON to load before watching")
                        .required(false)
                        .value_parser(clap::value_parser!(String)),
                ),
        )
        .subcommand(
            ClapCommand::new("create-whitelist")
                .about("Generate a custom whitelist JSON from observed traffic; optionally augment an existing custom whitelist")
                .arg(
                    arg!([SECONDS] "Capture duration in seconds before generating whitelist (default 60)")
                        .required(false)
                        .value_parser(clap::value_parser!(u64)),
                )
                .arg(
                    arg!([AUGMENT] "Augment existing custom whitelist instead of creating a fresh one")
                        .required(false)
                        .default_value("false")
                        .value_parser(clap::value_parser!(bool)),
                )
                .arg(
                    arg!(--file <PATH> "Output path for the generated (or augmented) whitelist JSON")
                        .required(false)
                        .value_parser(clap::value_parser!(String)),
                ),
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_scan_defaults() {
        let matches = build_cli()
            .try_get_matches_from(vec!["flodviddar", "scan", "120"])
            .expect("parse");
        let (sub, subm) = matches.subcommand().expect("sub");
        assert_eq!(sub, "scan");
        let subm = subm;
        assert!(!subm.get_flag("no-whitelist"));
        assert!(!subm.get_flag("until-signal"));
        assert_eq!(subm.get_one::<u64>("SECONDS").copied(), Some(120));
    }

    #[test]
    fn parse_scan_until_signal_output_whitelist() {
        let matches = build_cli()
            .try_get_matches_from(vec![
                "flodviddar",
                "scan",
                "--until-signal",
                "--output",
                "whitelist",
                "--no-anomaly",
            ])
            .expect("parse");
        let (_, subm) = matches.subcommand().unwrap();
        assert!(subm.get_flag("until-signal"));
        assert_eq!(
            subm.get_one::<String>("output").map(|s| s.as_str()),
            Some("whitelist")
        );
        assert!(subm.get_flag("no-anomaly"));
    }

    #[test]
    fn parse_watch_disable_cancel() {
        let matches = build_cli()
            .try_get_matches_from(vec!["flodviddar", "watch", "--no-cancel", "--no-blacklist"])
            .expect("parse");
        let (sc, subm) = matches.subcommand().unwrap();
        assert_eq!(sc, "watch");
        assert!(subm.get_flag("no-cancel"));
        assert!(subm.get_flag("no-blacklist"));
    }
}

async fn scan(
    seconds: u64,
    until_signal: bool,
    output_mode: Option<&str>,
    custom_wl: Option<&str>,
    check_whitelist: bool,
    check_blacklist: bool,
    check_anomaly: bool,
    cancel_pipeline: bool,
) -> Result<()> {
    // Discover network interfaces
    let interfaces = get_valid_network_interfaces();
    let capture = FlodbaddCapture::new();
    if let Some(path) = custom_wl {
        if std::path::Path::new(path).exists() {
            let json = std::fs::read_to_string(path)?;
            capture.set_custom_whitelists(&json).await;
        } else {
            eprintln!("Custom whitelist file '{}' not found, ignoring", path);
        }
    }

    // Start capture
    capture.start(&interfaces).await?;
    if until_signal {
        tracing::info!("Started capture; waiting for Ctrl-C/SIGTERM to stop");
        // Wait for either Ctrl-C or SIGTERM (Unix) / ctrl_close (Windows)
        #[cfg(not(target_os = "windows"))]
        {
            use tokio::signal::unix::{signal, SignalKind};
            let mut sigterm = signal(SignalKind::terminate())?;
            tokio::select! {
                _ = tokio::signal::ctrl_c() => {},
                _ = sigterm.recv() => {},
            }
        }
        #[cfg(target_os = "windows")]
        {
            tokio::signal::ctrl_c().await?;
        }
        tracing::info!("Signal received, stopping capture");
    } else {
        tracing::info!("Started capture for {seconds} seconds");
        sleep(Duration::from_secs(seconds)).await;
    }

    // Stop capture and analyze sessions
    let sessions = capture.get_sessions(false).await;
    tracing::info!("Captured {} sessions", sessions.len());

    let blacklisted = capture.get_blacklisted_sessions(false).await;

    // Run anomaly detection using SessionAnalyzer
    let analyzer = SessionAnalyzer::new();
    analyzer.start().await;
    let mut session_clone = sessions.clone();
    analyzer.analyze_sessions(&mut session_clone).await;
    let anomalous = analyzer.get_anomalous_sessions().await;

    let mut violations = false;
    let mut violating_sessions: Vec<flodbadd::sessions::SessionInfo> = Vec::new();

    if check_whitelist {
        let conform = capture.get_whitelist_conformance().await;
        if !conform {
            let exceptions = capture.get_whitelist_exceptions(false).await;
            println!("Whitelist exceptions detected: {}", exceptions.len());
            violations = true;
            violating_sessions.extend(exceptions);
        }
    }

    if check_blacklist && !blacklisted.is_empty() {
        println!("Blacklisted sessions detected: {}", blacklisted.len());
        violations = true;
        violating_sessions.extend(blacklisted.clone());
    }

    if check_anomaly && !anomalous.is_empty() {
        println!("Anomalous sessions detected: {}", anomalous.len());
        violations = true;
        violating_sessions.extend(anomalous.clone());
    }

    if cancel_pipeline && violations {
        // Print violating sessions report
        println!("\n=== Violating Sessions ===");
        for line in format_sessions_log(&violating_sessions) {
            println!("{}", line);
        }

        println!("\nPolicy violations detected. Halting CI pipeline...");
        halt_ci_pipeline("Flodviddar detected policy violations")?;
        std::process::exit(1);
    }

    // Always print a human-readable session report at the end
    println!("\n=== Session Report ===");
    for line in format_sessions_log(&sessions) {
        println!("{}", line);
    }

    // Handle requested output
    if let Some(mode) = output_mode {
        match mode {
            "whitelist" => {
                let json = capture.create_custom_whitelists().await?;
                println!("{}", json);
            }
            "report" => {
                // Dump sessions as JSON
                let json = serde_json::to_string_pretty(&sessions)?;
                println!("{}", json);
            }
            _ => {}
        }
    }

    Ok(())
}

async fn create_whitelist(seconds: u64, augment: bool, output_path: Option<&str>) -> Result<()> {
    let interfaces = get_valid_network_interfaces();
    let capture = FlodbaddCapture::new();
    capture.start(&interfaces).await?;

    tracing::info!("Capturing traffic for whitelist creation ({}s)", seconds);
    sleep(Duration::from_secs(seconds)).await;

    // If augmenting and file path provided & exists, load existing JSON first
    if augment {
        if let Some(path) = output_path {
            if std::path::Path::new(path).exists() {
                let existing = std::fs::read_to_string(path)?;
                capture.set_custom_whitelists(&existing).await;
            }
        }
    }

    let json = if augment {
        let (json, _) = capture.augment_custom_whitelists().await?;
        json
    } else {
        capture.create_custom_whitelists().await?
    };

    if let Some(path) = output_path {
        std::fs::write(path, &json)?;
        println!("Whitelist written to {}", path);
    } else {
        println!("{}", json);
    }

    Ok(())
}

/// Detects GitHub Actions or GitLab CI environment and attempts to cancel the current pipeline
/// First checks for external cancellation script, then falls back to built-in logic
fn halt_ci_pipeline(reason: &str) -> Result<()> {
    use std::env;
    use std::path::Path;
    
    // Check for custom cancellation script (most secure - no token passing needed)
    let cancel_script_path = env::var("FLODVIDDAR_CANCEL_SCRIPT")
        .unwrap_or_else(|_| {
            let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
            format!("{}/cancel_pipeline.sh", home)
        });
    
    // Try external script first if it exists
    if Path::new(&cancel_script_path).exists() {
        println!("Using cancellation script: {}", cancel_script_path);
        
        let status = Command::new("bash")
            .arg(&cancel_script_path)
            .arg(reason)
            .status();
        
        if let Ok(status) = status {
            if status.success() {
                println!("Pipeline cancelled successfully via script");
                return Ok(());
            } else {
                eprintln!("Cancellation script failed (exit code: {:?})", status.code());
            }
        } else {
            eprintln!("Failed to execute cancellation script");
        }
    } else {
        println!("No cancellation script found at {}, using built-in logic", cancel_script_path);
    }
    
    // Fallback to built-in cancellation logic
    // GitHub Actions detection
    if std::env::var("GITHUB_ACTIONS").is_ok() {
        if let (Ok(run_id), Ok(repo)) = (
            std::env::var("GITHUB_RUN_ID"),
            std::env::var("GITHUB_REPOSITORY"),
        ) {
            println!("Attempting to cancel GitHub Actions run {run_id} for repo {repo}…");
            let status = Command::new("gh")
                .args(["run", "cancel", &run_id, "--repo", &repo])
                .status();

            if let Ok(status) = status {
                if status.success() {
                    println!("GitHub Actions run cancelled successfully");
                } else {
                    eprintln!("Failed to cancel GitHub Actions run (exit code {})", status);
                }
            } else {
                eprintln!("Failed to execute 'gh' command. Is GitHub CLI installed?");
            }
        } else {
            eprintln!("Missing GITHUB_RUN_ID or GITHUB_REPOSITORY env vars; cannot cancel run");
        }
    }
    // GitLab detection
    else if std::env::var("GITLAB_CI").is_ok() {
        if let (Ok(project_id), Ok(pipeline_id), Ok(token)) = (
            std::env::var("CI_PROJECT_ID"),
            std::env::var("CI_PIPELINE_ID"),
            std::env::var("GITLAB_TOKEN"),
        ) {
            println!(
                "Attempting to cancel GitLab pipeline {pipeline_id} for project {project_id}…"
            );
            let url = format!(
                "https://gitlab.com/api/v4/projects/{}/pipelines/{}/cancel",
                project_id, pipeline_id
            );
            let status = Command::new("curl")
                .args([
                    "-s",
                    "-X",
                    "POST",
                    "-H",
                    &format!("PRIVATE-TOKEN: {}", token),
                    &url,
                ])
                .status();
            if let Ok(status) = status {
                if status.success() {
                    println!("GitLab pipeline cancelled successfully");
                } else {
                    eprintln!("Failed to cancel GitLab pipeline (exit code {})", status);
                }
            } else {
                eprintln!("Failed to execute 'curl' command. Is curl installed?");
            }
        } else {
            eprintln!("Missing CI_PROJECT_ID / CI_PIPELINE_ID / GITLAB_TOKEN env vars; cannot cancel pipeline");
        }
    }

    Ok(())
}
