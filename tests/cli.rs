use assert_cmd::cargo::CommandCargoExt;
use predicates::str::contains;
use std::process::Command;

#[test]
fn help_displays() {
    let mut cmd = Command::cargo_bin("flodviddar").expect("binary");
    cmd.arg("--help")
        .assert()
        .success()
        .stdout(contains("CI-aware egress network threat detector"));
}
