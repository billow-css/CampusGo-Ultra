#!/usr/bin/env bash
# Build on the oldest Fedora release that you intend to support.
set -euo pipefail

usage() {
  echo "Usage: bash Tools/build-fedora.sh [--install-deps] [--check]"
  echo "Builds an x86_64 Fedora RPM; output: dist/fedora-x86_64/"
}

install_deps=false
check_only=false
for arg in "$@"; do
  case "$arg" in
    --install-deps) install_deps=true ;;
    --check) check_only=true ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || {
  echo "Run this script on x86_64 Linux (Fedora), not Windows/macOS." >&2
  exit 1
}
source /etc/os-release
[[ "${ID:-}" == fedora ]] || {
  echo "This dependency installer and RPM configuration target Fedora." >&2
  exit 1
}

if "$install_deps"; then
  elevate=()
  if (( EUID != 0 )); then elevate=(sudo); fi
  "${elevate[@]}" dnf install -y gcc gcc-c++ make pkgconf-pkg-config \
    webkit2gtk4.1-devel openssl-devel libappindicator-gtk3-devel \
    librsvg2-devel libxdo-devel curl wget file patchelf rpm-build \
    nodejs npm rust cargo
fi

for cmd in node npm rustc cargo gcc g++ pkg-config rpm file sha256sum; do
  command -v "$cmd" >/dev/null || {
    echo "Missing $cmd. Run with --install-deps, or install the prerequisites." >&2
    exit 1
  }
done
node --input-type=module -e '
  const [major, minor] = process.versions.node.split(".").map(Number);
  if (major < 22 || (major === 22 && minor < 12)) {
    console.error("Node.js 22.12+ is required."); process.exit(1);
  }
'
pkg-config --exists webkit2gtk-4.1 gtk+-3.0
rust_version="$(rustc --version)"
IFS=. read -r rust_major rust_minor _ <<< "${rust_version#rustc }"
if (( rust_major < 1 || (rust_major == 1 && rust_minor < 90) )); then
  echo "Rust 1.90+ is required by the locked Tauri dependencies. Install a newer stable toolchain." >&2
  exit 1
fi
node --version
npm --version
echo "$rust_version"
cargo --version
echo "Build platform: ${PRETTY_NAME:-Fedora}, $(uname -m)"
if "$check_only"; then exit 0; fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir/Desktop"
target=x86_64-unknown-linux-gnu
# Keep the output path deterministic even if the caller configured another target dir.
export CARGO_TARGET_DIR="$PWD/src-tauri/target"
npm ci
npm run build
npm test
cargo test --release --locked --features tauri/custom-protocol --manifest-path src-tauri/Cargo.toml --target "$target"
npm run tauri -- build --ci --target "$target" --bundles rpm -- --locked

out="$repo_dir/dist/fedora-x86_64"
mkdir -p "$out"
shopt -s nullglob
packages=("$CARGO_TARGET_DIR/$target/release/bundle/rpm/"*.rpm)
(( ${#packages[@]} == 1 )) || {
  echo "Expected exactly one RPM, found ${#packages[@]}; inspect the bundle directory." >&2
  exit 1
}
rpm -qp --qf '%{NAME} %{VERSION}-%{RELEASE} %{ARCH}\n' "${packages[0]}"
[[ "$(rpm -qp --qf '%{ARCH}' "${packages[0]}")" == x86_64 ]]
rpm -qpl "${packages[0]}" | grep -q '/usr/bin/campusgo-desktop$'
cp -- "${packages[0]}" "$out/"
package_name="$(basename -- "${packages[0]}")"
rpm -qpR "${packages[0]}" > "$out/RPM-REQUIRES.txt"
rpm -qpl "${packages[0]}" > "$out/RPM-FILES.txt"
cp -- "$repo_dir/LICENSE" "$repo_dir/NOTICE" "$repo_dir/Docs/Fedora.md" "$out/"
{
  printf 'Built: %s\nPlatform: %s\n' "$(date -u +%FT%TZ)" "${PRETTY_NAME:-Fedora}"
  printf 'Target: %s\n' "$target"
  rustc --version
  node --version
  echo 'Frontend logic tests and Rust tests passed during this build.'
  echo 'Desktop installation and GUI behavior require testing on the target Fedora system.'
} > "$out/BUILD-INFO.txt"
(cd "$out" && sha256sum -- "$package_name" > SHA256SUMS.txt)
printf '\nRPM ready: %s/%s\nInstall: sudo dnf install "%s/%s"\n' \
  "$out" "$package_name" "$out" "$package_name"
