use std::time::Duration;

use anyhow::Result;
use flodbadd::{
    analyzer::SessionAnalyzer,
    capture::FlodbaddCapture,
    interface::get_valid_network_interfaces,
    sessions::{format_sessions_log, SessionInfo},
};
use tokio::time::interval;
use tracing::info;

/// Run the monitoring loop.  This never returns unless an error occurs or a
/// policy violation is detected.
///
/// * `poll_every` – number of seconds between anomaly checks.
/// * `fail_on_violation` – whether to cancel the CI pipeline and exit 1 when a violation is found.
///
pub async fn watch_daemon(
    poll_every: u64,
    check_whitelist: bool,
    check_blacklist: bool,
    check_anomaly: bool,
    cancel_on_violation: bool,
    custom_wl: Option<&str>,
) -> Result<()> {
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
    capture.start(&interfaces).await?;

    // Initialize analyzer for anomaly detection
    let analyzer = SessionAnalyzer::new();
    analyzer.start().await;

    info!("Flodviddar daemon started – polling every {poll_every}s");
    let mut ticker = interval(Duration::from_secs(poll_every));

    loop {
        ticker.tick().await; // wait for next tick

        let mut violations = false;
        let mut violating_sessions: Vec<SessionInfo> = Vec::new();

        // Update analyzer with new sessions
        let mut new_sessions = capture.get_sessions(true).await;
        if !new_sessions.is_empty() {
            analyzer.analyze_sessions(&mut new_sessions).await;
        }

        if check_whitelist {
            let conformance = capture.get_whitelist_conformance().await;
            if !conformance {
                let exceptions = capture.get_whitelist_exceptions(false).await;
                info!("Whitelist exceptions detected: {}", exceptions.len());
                violations = true;
                violating_sessions.extend(exceptions);
            }
        }

        if check_blacklist {
            let blacklisted = capture.get_blacklisted_sessions(false).await;
            if !blacklisted.is_empty() {
                info!("Blacklisted sessions detected: {}", blacklisted.len());
                violations = true;
                violating_sessions.extend(blacklisted.clone());
            }
        }

        if check_anomaly {
            let anomalous = analyzer.get_anomalous_sessions().await;
            if !anomalous.is_empty() {
                info!("Anomalous sessions detected: {}", anomalous.len());
                violations = true;
                violating_sessions.extend(anomalous.clone());
            }
        }

        if violations {
            println!("\n=== Violating Sessions ===");
            for line in format_sessions_log(&violating_sessions) {
                println!("{}", line);
            }
            println!("Policy violations detected");
            std::process::exit(1);
        }

        if cancel_on_violation && violations {
            println!("\n=== Violating Sessions ===");
            for line in format_sessions_log(&violating_sessions) {
                println!("{}", line);
            }
            println!("Policy violations detected. Cancelling CI pipeline...");
            let _ = super::halt_ci_pipeline("Flodviddar daemon detected violations");
            std::process::exit(1);
        }
    }
}
