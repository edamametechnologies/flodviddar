use assert_cmd::Command;
use predicates::str::contains;

#[test]
fn help_displays() {
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_flodviddar"));
    cmd.arg("--help")
        .assert()
        .success()
        .stdout(contains("CI-aware egress network threat detector"));
}
