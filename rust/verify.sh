#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# No GUI launch, camera, permission prompt or user preference access.
cargo fmt --check
cargo test --locked
if [[ "$(uname -s)" == Darwin ]]; then
# Compile the patched legacy ABI declaration without Cargo's dependency lint cap.
# This fails on the original uninhabited static and on implicit-ABI warnings.
block_check="$(mktemp -d "${TMPDIR:-/tmp}/anotchup-block-check.XXXXXX")"
trap 'rm -rf "$block_check"' EXIT
rustc --edition=2015 --crate-name block --crate-type lib --emit=metadata \
    -D warnings vendor/block/src/lib.rs --out-dir "$block_check"
host="$(rustc -vV | awk '/^host:/ {print $2}')"
cargo metadata --format-version 1 --locked --features gui --filter-platform "$host" | python3 -c '
import json, pathlib, sys
metadata = json.load(sys.stdin)
revision = "81742184cb1df090709257a5e4061eba44fa8e8a"
source = f"git+https://github.com/gpui-ce/gpui-ce?rev={revision}#{revision}"
family = [p for p in metadata["packages"] if "github.com/gpui-ce/gpui-ce" in (p.get("source") or "")]
assert family and all(p["source"] == source for p in family)
for name in ["gpui-ce", "gpui_ce_platform"]:
    assert len([p for p in family if p["name"] == name]) == 1, name
backends = [p for p in metadata["packages"] if p["name"] == "gpui_ce_macos"]
assert len(backends) == 1 and backends[0]["source"] is None
assert pathlib.Path(backends[0]["manifest_path"]).resolve() == pathlib.Path("vendor/gpui_ce_macos/Cargo.toml").resolve()
blocks = [p for p in metadata["packages"] if p["name"] == "block"]
assert len(blocks) == 1 and blocks[0]["source"] is None
assert pathlib.Path(blocks[0]["manifest_path"]).resolve() == pathlib.Path("vendor/block/Cargo.toml").resolve()
print("One pinned GPUI-CE family, one local macOS backend, and one patched block ABI dependency.")
'
    cargo clippy --locked --all-targets --features gui -- -D warnings
    cargo build --locked --features gui
    cargo run --locked --features gui -- --check-native
else
    cargo clippy --locked --all-targets -- -D warnings
    echo 'Native macOS build/contracts skipped on this platform.'
fi
