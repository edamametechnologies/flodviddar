use assert_cmd::Command;
use predicates::str::contains;

#[test]
fn help_displays() {
    let mut cmd = Command::cargo_bin("flodviddar").expect("binary");
    cmd.arg("--help")
        .assert()
        .success()
        .stdout(contains("CI-aware egress network threat detector"));
}
