#!/usr/bin/env bash
# Build a Rust crate's release binary from the caller's repo root, ad-hoc
# codesigning it on macOS so keychain ACLs survive rebuilds. Hoisted from
# pigeon-cli by its CLI-0161; the codesign step is its CLI-0016.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: crate-build-release.sh --bin NAME --codesign-id ID [--target <triple>]

  --bin          The binary's name, e.g. pigeon.
  --codesign-id  Identifier for the macOS ad-hoc codesign, e.g.
                 dev.pigeon.cli. Ignored off macOS.
  --target       Rust target triple to build for, e.g. x86_64-apple-darwin.
                 Installs the target via `rustup target add` first; binary
                 lands at target/<triple>/release/<bin>. When omitted, runs
                 a plain `cargo build --release` for the host's native
                 target, landing at target/release/<bin>.
EOF
}

target=""
bin=""
codesign_id=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bin) bin="$2"; shift 2 ;;
    --codesign-id) codesign_id="$2"; shift 2 ;;
    --target) target="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [ -z "$bin" ] || [ -z "$codesign_id" ]; then
  echo "--bin and --codesign-id are required." >&2
  usage >&2
  exit 1
fi

if [ -n "$target" ]; then
  rustup target add "$target"
  cargo build --release --target "$target"
  bin_path="target/${target}/release/${bin}"
else
  cargo build --release
  bin_path="target/release/${bin}"
fi

if [ "$(uname)" = "Darwin" ]; then
  codesign --force -s - --identifier "$codesign_id" "$bin_path"
fi
